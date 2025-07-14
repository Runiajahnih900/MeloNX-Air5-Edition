using System;
using System.Runtime.InteropServices;
using System.Diagnostics;
using Ryujinx.Common.Logging;

namespace Ryujinx.Memory
{
    /// <summary>
    /// Placeholder class for JIT memory allocation on iOS.
    /// Intended to allocate memory with both r/x and r/w permissions,
    /// as a workaround for stricter W^X (Write XOR Execute) enforcement introduced in iOS 26.
    /// 
    /// Specifically targets iOS 26, where the traditional method of reprotecting
    /// memory from writable to executable (RX) no longer works for JIT code.
    /// 
    /// The actual allocation logic will be implemented after the release of iOS 26
    /// to reduce the risk of this workaround being patched.
    /// </summary>
    public class DualMappedJitAllocator : IDisposable
    {

        public IntPtr RwPtr { get; private set; }
        public IntPtr RxPtr { get; private set; }
        public ulong Size { get; private set; }


        private IntPtr _mmapPtr;

        public DualMappedJitAllocator(ulong size)
        {
            var stackTrace = new StackTrace(1, false);
            var callingMethod = stackTrace.GetFrame(0)?.GetMethod();

            Logger.Info?.Print(LogClass.Cpu,
                $"Allocating dual-mapped JIT memory of size {size} bytes, called by {callingMethod?.DeclaringType?.FullName}.{callingMethod?.Name}");
            Size = size;
            AllocateDualMapping();
        }


        private void AllocateDualMapping()
        {

            RwPtr = IntPtr.Zero;
            RxPtr = IntPtr.Zero;
        }

        public void Dispose()
        {

        }
    }
}
