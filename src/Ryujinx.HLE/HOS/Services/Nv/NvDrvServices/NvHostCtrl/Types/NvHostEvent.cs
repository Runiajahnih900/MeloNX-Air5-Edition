using Ryujinx.Common.Logging;
using Ryujinx.Graphics.Gpu;
using Ryujinx.Graphics.Gpu.Synchronization;
using Ryujinx.HLE.HOS.Kernel;
using Ryujinx.HLE.HOS.Kernel.Threading;
using Ryujinx.HLE.HOS.Services.Nv.Types;
using Ryujinx.Horizon.Common;
using System;
using System.Threading;

namespace Ryujinx.HLE.HOS.Services.Nv.NvDrvServices.NvHostCtrl
{
    class NvHostEvent
    {
        public NvFence Fence;
        public NvHostEventState State;
        public KEvent Event;
        public int EventHandle;

        private readonly uint _eventId;
        private readonly NvHostSyncpt _syncpointManager;
        private SyncpointWaiterHandle _waiterInformation;

        private NvFence _previousFailingFence;
        private uint _failingCount;
        private NvFence _previousIosSmallDeltaFence;
        private uint _previousIosSmallDeltaSyncpointValue;
        private uint _iosSmallDeltaStallCount;

        public readonly object Lock = new();

        /// <summary>
        /// Max failing count until waiting on CPU.
        /// FIXME: This seems enough for most of the cases, reduce if needed.
        /// </summary>
        private const uint FailingCountMax = 2;
        private const uint IosSkipCpuWaitDeltaThreshold = 2;
        private const uint IosSmallDeltaForceSuccessThreshold = 2;
        private static readonly TimeSpan IosBlockingCpuWaitTimeout = TimeSpan.FromMilliseconds(120);
        private static readonly TimeSpan IosCpuWaitTimeout = TimeSpan.FromMilliseconds(16);
        private static readonly bool IosNvWaitPromotionEnabled =
            string.Equals(Environment.GetEnvironmentVariable("MELONX_IOS_NV_WAIT_PROMOTION"), "1", StringComparison.Ordinal);
        private static readonly bool IosNvWaitBlockingEnabled =
            string.Equals(Environment.GetEnvironmentVariable("MELONX_IOS_NV_WAIT_BLOCKING"), "1", StringComparison.Ordinal);

        public NvHostEvent(NvHostSyncpt syncpointManager, uint eventId, Horizon system)
        {
            Fence.Id = 0;

            State = NvHostEventState.Available;

            Event = new KEvent(system.KernelContext);

            if (KernelStatic.GetCurrentProcess().HandleTable.GenerateHandle(Event.ReadableEvent, out EventHandle) != Result.Success)
            {
                throw new InvalidOperationException("Out of handles!");
            }

            _eventId = eventId;

            _syncpointManager = syncpointManager;

            ResetFailingState();
            ResetIosSmallDeltaStallState();
        }

        private void ResetFailingState()
        {
            _previousFailingFence.Id = NvFence.InvalidSyncPointId;
            _previousFailingFence.Value = 0;
            _failingCount = 0;
        }

        private void ResetIosSmallDeltaStallState()
        {
            _previousIosSmallDeltaFence.Id = NvFence.InvalidSyncPointId;
            _previousIosSmallDeltaFence.Value = 0;
            _previousIosSmallDeltaSyncpointValue = 0;
            _iosSmallDeltaStallCount = 0;
        }

        private void PromoteIosSyncpointOnForcedSuccess(GpuContext gpuContext, uint currentSyncpointValue)
        {
            uint remainingSyncpointDelta = Fence.Value > currentSyncpointValue ? Fence.Value - currentSyncpointValue : 0;

            if (!OperatingSystem.IsIOS() || !IosNvWaitPromotionEnabled || remainingSyncpointDelta == 0 || remainingSyncpointDelta > IosSkipCpuWaitDeltaThreshold)
            {
                return;
            }

            for (uint i = 0; i < remainingSyncpointDelta; i++)
            {
                _syncpointManager.Increment(Fence.Id);
            }

            uint promotedSyncpointValue = gpuContext.Synchronization.GetSyncpointValue(Fence.Id);

            Logger.Warning?.Print(
                LogClass.ServiceNv,
                $"MELONX_IOS_NV_WAIT_V5: promoted syncpoint after forced success. syncpt={Fence.Id}, target={Fence.Value}, previousCurrent={currentSyncpointValue}, promotedCurrent={promotedSyncpointValue}, promotedBy={remainingSyncpointDelta}");
        }

        private void Signal()
        {
            lock (Lock)
            {
                NvHostEventState oldState = State;

                State = NvHostEventState.Signaling;

                if (oldState == NvHostEventState.Waiting)
                {
                    Event.WritableEvent.Signal();
                }

                State = NvHostEventState.Signaled;
            }
        }

        private void GpuSignaled(SyncpointWaiterHandle waiterInformation)
        {
            lock (Lock)
            {
                // If the signal does not match our current waiter,
                // then it is from a past fence and we should just ignore it.
                if (waiterInformation != null && waiterInformation != _waiterInformation)
                {
                    return;
                }

                ResetFailingState();
                ResetIosSmallDeltaStallState();

                Signal();
            }
        }

        public void Cancel(GpuContext gpuContext)
        {
            lock (Lock)
            {
                NvHostEventState oldState = State;

                State = NvHostEventState.Cancelling;

                if (oldState == NvHostEventState.Waiting && _waiterInformation != null)
                {
                    gpuContext.Synchronization.UnregisterCallback(Fence.Id, _waiterInformation);
                    _waiterInformation = null;

                    if (_previousFailingFence.Id == Fence.Id && _previousFailingFence.Value == Fence.Value)
                    {
                        _failingCount++;
                    }
                    else
                    {
                        _failingCount = 1;

                        _previousFailingFence = Fence;
                    }
                }

                State = NvHostEventState.Cancelled;

                Event.WritableEvent.Clear();
            }
        }

        public bool Wait(GpuContext gpuContext, NvFence fence)
        {
            lock (Lock)
            {
                // NOTE: nvservices code should always wait on the GPU side.
                //       If we do this, we may get an abort or undefined behaviour when the GPU processing thread is blocked for a long period (for example, during shader compilation).
                //       The reason for this is that the NVN code will try to wait until giving up.
                //       This is done by trying to wait and signal multiple times until aborting after you are past the timeout.
                //       As such, if it fails too many time, we enforce a wait on the CPU side indefinitely.
                //       This allows to keep GPU and CPU in sync when we are slow.
                if (_failingCount == FailingCountMax)
                {
                    bool isIos = OperatingSystem.IsIOS();
                    uint currentSyncpointValue = gpuContext.Synchronization.GetSyncpointValue(Fence.Id);
                    uint remainingSyncpointDelta = Fence.Value > currentSyncpointValue ? Fence.Value - currentSyncpointValue : 0;
                    Logger.Warning?.Print(
                        LogClass.ServiceNv,
                        $"MELONX_IOS_NV_WAIT_V5: GPU processing thread is too slow, waiting on CPU... syncpt={Fence.Id}, target={Fence.Value}, current={currentSyncpointValue}, remaining={remainingSyncpointDelta}, failingCount={_failingCount}, isIos={isIos}");

                    if (isIos)
                    {
                        if (IosNvWaitBlockingEnabled)
                        {
                            bool blockingSignaled = Fence.Wait(gpuContext, IosBlockingCpuWaitTimeout);

                            uint blockingUpdatedSyncpointValue = gpuContext.Synchronization.GetSyncpointValue(Fence.Id);

                            if (blockingSignaled)
                            {
                                Logger.Warning?.Print(
                                    LogClass.ServiceNv,
                                    $"MELONX_IOS_NV_WAIT_V6: blocking CPU wait enabled on iOS, waited until fence signal. syncpt={Fence.Id}, target={Fence.Value}, current={blockingUpdatedSyncpointValue}");

                                ResetFailingState();
                                ResetIosSmallDeltaStallState();

                                return false;
                            }

                            Logger.Warning?.Print(
                                LogClass.ServiceNv,
                                $"MELONX_IOS_NV_WAIT_V6: blocking CPU wait timed out after {IosBlockingCpuWaitTimeout.TotalMilliseconds}ms, continuing with TryAgain to avoid deadlock. syncpt={Fence.Id}, target={Fence.Value}, current={blockingUpdatedSyncpointValue}");

                            ResetFailingState();
                            ResetIosSmallDeltaStallState();

                            return true;
                        }

                        if (IosNvWaitPromotionEnabled && remainingSyncpointDelta <= IosSkipCpuWaitDeltaThreshold)
                        {
                            bool sameFenceAndSyncpoint = _previousIosSmallDeltaFence.Id == Fence.Id &&
                                                         _previousIosSmallDeltaFence.Value == Fence.Value &&
                                                         _previousIosSmallDeltaSyncpointValue == currentSyncpointValue;

                            if (sameFenceAndSyncpoint)
                            {
                                _iosSmallDeltaStallCount++;
                            }
                            else
                            {
                                _iosSmallDeltaStallCount = 1;
                                _previousIosSmallDeltaFence = Fence;
                                _previousIosSmallDeltaSyncpointValue = currentSyncpointValue;
                            }

                            Logger.Warning?.Print(
                                LogClass.ServiceNv,
                                $"MELONX_IOS_NV_WAIT_V5: skipping CPU wait on iOS for small syncpoint delta (remaining={remainingSyncpointDelta} <= {IosSkipCpuWaitDeltaThreshold}), stallCount={_iosSmallDeltaStallCount}, returning TryAgain.");

                            if (_iosSmallDeltaStallCount >= IosSmallDeltaForceSuccessThreshold)
                            {
                                Logger.Warning?.Print(
                                    LogClass.ServiceNv,
                                    $"MELONX_IOS_NV_WAIT_V5: small-delta stall persisted for fence, forcing Success to break TryAgain loop. syncpt={Fence.Id}, target={Fence.Value}, current={currentSyncpointValue}, stallCount={_iosSmallDeltaStallCount}");

                                PromoteIosSyncpointOnForcedSuccess(gpuContext, currentSyncpointValue);

                                ResetFailingState();
                                ResetIosSmallDeltaStallState();

                                return false;
                            }

                            ResetFailingState();

                            return true;
                        }

                        ResetIosSmallDeltaStallState();

                        bool signaled = Fence.Wait(gpuContext, IosCpuWaitTimeout);
                        uint updatedSyncpointValue = gpuContext.Synchronization.GetSyncpointValue(Fence.Id);

                        if (!signaled)
                        {
                            Logger.Warning?.Print(
                                LogClass.ServiceNv,
                                $"MELONX_IOS_NV_WAIT_V5: bounded CPU wait timed out after {IosCpuWaitTimeout.TotalMilliseconds}ms, continuing with TryAgain. syncpt={Fence.Id}, target={Fence.Value}, current={updatedSyncpointValue}");
                        }

                        ResetFailingState();

                        // true => TryAgain (not signaled yet), false => Success (fence reached)
                        return !signaled;
                    }

                    Fence.Wait(gpuContext, Timeout.InfiniteTimeSpan);

                    ResetFailingState();
                    ResetIosSmallDeltaStallState();

                    return false;
                }
                else
                {
                    Fence = fence;
                    State = NvHostEventState.Waiting;

                    _waiterInformation = gpuContext.Synchronization.RegisterCallbackOnSyncpoint(Fence.Id, Fence.Value, GpuSignaled);

                    return true;
                }
            }
        }

        public string DumpState(GpuContext gpuContext)
        {
            string res = $"\nNvHostEvent {_eventId}:\n";
            res += $"\tState: {State}\n";

            if (State == NvHostEventState.Waiting)
            {
                res += "\tFence:\n";
                res += $"\t\tId            : {Fence.Id}\n";
                res += $"\t\tThreshold     : {Fence.Value}\n";
                res += $"\t\tCurrent Value : {gpuContext.Synchronization.GetSyncpointValue(Fence.Id)}\n";
                res += $"\t\tWaiter Valid  : {_waiterInformation != null}\n";
            }

            return res;
        }

        public void CloseEvent(ServiceCtx context)
        {
            if (EventHandle != 0)
            {
                context.Process.HandleTable.CloseHandle(EventHandle);
                EventHandle = 0;
            }
        }
    }
}
