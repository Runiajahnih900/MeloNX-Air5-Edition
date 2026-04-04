using Ryujinx.Common.Logging;
using Ryujinx.Graphics.Gpu;
using Ryujinx.Graphics.Gpu.Synchronization;
using Ryujinx.HLE.HOS.Services.Nv.Types;
using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Threading;

namespace Ryujinx.HLE.HOS.Services.SurfaceFlinger
{
    [StructLayout(LayoutKind.Sequential, Pack = 1, Size = 0x24)]
    struct AndroidFence : IFlattenable
    {
        public int FenceCount;

        private byte _fenceStorageStart;

        private Span<byte> Storage => MemoryMarshal.CreateSpan(ref _fenceStorageStart, Unsafe.SizeOf<NvFence>() * 4);

        public Span<NvFence> NvFences => MemoryMarshal.Cast<byte, NvFence>(Storage);

        public static AndroidFence NoFence
        {
            get
            {
                AndroidFence fence = new()
                {
                    FenceCount = 0,
                };

                fence.NvFences[0].Id = NvFence.InvalidSyncPointId;

                return fence;
            }
        }

        public void AddFence(NvFence fence)
        {
            NvFences[FenceCount++] = fence;
        }

        private static readonly bool _iosSosCrashResilience =
            OperatingSystem.IsIOS() &&
            string.Equals(Environment.GetEnvironmentVariable("MELONX_IOS_SOS_CRASH_RESILIENCE"), "1", StringComparison.Ordinal);

        public void WaitForever(GpuContext gpuContext)
        {
            bool hasTimeout = Wait(gpuContext, TimeSpan.FromMilliseconds(3000));

            if (hasTimeout)
            {
                if (_iosSosCrashResilience)
                {
                    // Under crash resilience (Story of Seasons save-load), do NOT wait infinitely.
                    // The syncpoint promotion in NvHostEvent may have desynchronized the GPU state,
                    // so an infinite wait here would deadlock the render loop causing a white screen.
                    // Instead, try one more bounded wait, then proceed regardless.
                    Logger.Warning?.Print(LogClass.SurfaceFlinger,
                        "MELONX_IOS_FENCE_RESILIENCE: Android fence didn't signal in 3000ms. " +
                        "Attempting bounded recovery wait instead of infinite block.");

                    bool stillTimeout = Wait(gpuContext, TimeSpan.FromMilliseconds(1000));

                    if (stillTimeout)
                    {
                        Logger.Warning?.Print(LogClass.SurfaceFlinger,
                            "MELONX_IOS_FENCE_RESILIENCE: Recovery wait also timed out after 1000ms. " +
                            "Proceeding without fence completion to avoid white-screen deadlock.");
                    }

                    return;
                }

                Logger.Error?.Print(LogClass.SurfaceFlinger, "Android fence didn't signal in 3000 ms");
                Wait(gpuContext, Timeout.InfiniteTimeSpan);
            }

        }

        public bool Wait(GpuContext gpuContext, TimeSpan timeout)
        {
            for (int i = 0; i < FenceCount; i++)
            {
                bool hasTimeout = NvFences[i].Wait(gpuContext, timeout);

                if (hasTimeout)
                {
                    return true;
                }
            }

            return false;
        }

        public void RegisterCallback(GpuContext gpuContext, Action<SyncpointWaiterHandle> callback)
        {
            ref NvFence fence = ref NvFences[FenceCount - 1];

            if (fence.IsValid())
            {
                gpuContext.Synchronization.RegisterCallbackOnSyncpoint(fence.Id, fence.Value, callback);
            }
            else
            {
                callback(null);
            }
        }

        public readonly uint GetFlattenedSize()
        {
            return (uint)Unsafe.SizeOf<AndroidFence>();
        }

        public readonly uint GetFdCount()
        {
            return 0;
        }

        public void Flatten(Parcel parcel)
        {
            parcel.WriteUnmanagedType(ref this);
        }

        public void Unflatten(Parcel parcel)
        {
            this = parcel.ReadUnmanagedType<AndroidFence>();
        }
    }
}
