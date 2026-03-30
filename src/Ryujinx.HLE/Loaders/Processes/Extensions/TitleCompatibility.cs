using System;

namespace Ryujinx.HLE.Loaders.Processes.Extensions
{
    internal static class TitleCompatibility
    {
        public const ulong EastwardProgramId = 0x010071b00f63a000UL;

        public static bool ShouldDisableModInjection(ulong programId)
        {
            return OperatingSystem.IsIOS() && programId == EastwardProgramId;
        }
    }
}
