// System accessibility settings for the device lab's accessibility matrix: contrast themes,
// client-area animations ("Animation effects"), transparency effects and text scaling.
// uiwin.py applies them only while it holds the desktop lock and always restores the previous
// values before releasing it, because they change the operator's real desktop.

using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using Microsoft.Win32;

namespace FstUia;

internal sealed partial class Driver
{
    #region sysset

    /// <summary>
    /// Windows 11 contrast theme → legacy high-contrast scheme display name (SPI_SETHIGHCONTRAST ignores the registry's
    /// <c>@themeui.dll,-85x</c> names); the window colours match the <c>Ease of Access Themes</c> files.
    /// </summary>
    private static readonly Dictionary<string, string> ContrastSchemes = new(StringComparer.OrdinalIgnoreCase)
    {
        ["dusk"] = "High Contrast #1",       // hc1.theme, #2D3236 window
        ["night-sky"] = "High Contrast #2",  // hc2.theme, #000000 window
        ["aquatic"] = "High Contrast Black", // hcblack.theme, #202020 window
        ["desert"] = "High Contrast White",  // hcwhite.theme, #FFFAEF window
    };

    /// <summary>
    /// <c>sysset</c>: applies any of <c>high_contrast</c> (<c>off</c>, <c>aquatic</c>, <c>desert</c>, <c>dusk</c>,
    /// <c>night-sky</c> or a raw scheme name), <c>animations</c> (bool), <c>transparency</c> (bool),
    /// <c>light_theme</c> (bool, the default app mode), <c>display_scale</c> (percent, primary display) and
    /// <c>text_scale</c> (100–225) and returns the values before and after, so the caller can restore them.
    /// </summary>
    /// <param name="request">Request with a <c>set</c> object.</param>
    /// <returns><c>previous</c> and <c>current</c> setting objects.</returns>
    private static JsonNode SysSet(JsonObject request)
    {
        var previous = ReadSettings();
        var set = request["set"]?.AsObject() ?? [];
        if (set["high_contrast"] is JsonNode contrast) SetHighContrast((string)contrast!);
        if (set["animations"] is JsonNode animations) SetAnimations((bool)animations!);
        if (set["transparency"] is JsonNode transparency) SetTransparency((bool)transparency!);
        if (set["text_scale"] is JsonNode scale) SetTextScale((int)scale!);
        if (set["light_theme"] is JsonNode light) SetLightTheme((bool)light!);
        if (set["display_scale"] is JsonNode displayScale) DisplayScale.Set((int)displayScale!);
        return new JsonObject { ["previous"] = previous, ["current"] = ReadSettings() };
    }

    /// <summary>Current values in the same shape <c>set</c> accepts.</summary>
    /// <returns>Settings object.</returns>
    private static JsonObject ReadSettings()
    {
        var hc = new HighContrast { Size = (uint)Marshal.SizeOf<HighContrast>() };
        SystemParametersInfo(SpiGetHighContrast, hc.Size, ref hc, 0);
        var scheme = hc.DefaultScheme == IntPtr.Zero ? "" : Marshal.PtrToStringUni(hc.DefaultScheme) ?? "";
        var named = ContrastSchemes.FirstOrDefault(p => p.Value.Equals(scheme, StringComparison.OrdinalIgnoreCase)).Key;
        var animations = false;
        SystemParametersInfo(SpiGetClientAreaAnimation, 0, ref animations, 0);
        using var personalize = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
        using var accessibility = Registry.CurrentUser.OpenSubKey(AccessibilityKey);
        return new JsonObject
        {
            ["high_contrast"] = (hc.Flags & HcfHighContrastOn) != 0 ? named ?? scheme : "off",
            ["animations"] = animations,
            ["transparency"] = (personalize?.GetValue("EnableTransparency") as int? ?? 1) != 0,
            ["text_scale"] = accessibility?.GetValue("TextScaleFactor") as int? ?? 100,
            ["light_theme"] = (personalize?.GetValue("AppsUseLightTheme") as int? ?? 1) != 0,
            ["display_scale"] = DisplayScale.Get(),
            ["window_color"] = $"#{GetSysColor(ColorWindow) & 0xFF:X2}{(GetSysColor(ColorWindow) >> 8) & 0xFF:X2}{(GetSysColor(ColorWindow) >> 16) & 0xFF:X2}",
        };
    }

    private static void SetHighContrast(string value)
    {
        var on = !value.Equals("off", StringComparison.OrdinalIgnoreCase);
        var scheme = ContrastSchemes.GetValueOrDefault(value, value);
        var text = on ? Marshal.StringToHGlobalUni(scheme) : IntPtr.Zero;
        try
        {
            var hc = new HighContrast
            {
                Size = (uint)Marshal.SizeOf<HighContrast>(),
                Flags = on ? HcfHighContrastOn : 0,
                DefaultScheme = text,
            };
            if (!SystemParametersInfo(SpiSetHighContrast, hc.Size, ref hc, SpifUpdateIniFile | SpifSendChange))
                throw new InvalidOperationException($"SPI_SETHIGHCONTRAST failed ({Marshal.GetLastWin32Error()})");
        }
        finally
        {
            if (text != IntPtr.Zero) Marshal.FreeHGlobal(text);
        }
        Thread.Sleep(1500); // themes re-render every window
    }

    private static void SetAnimations(bool enabled)
    {
        if (!SystemParametersInfo(SpiSetClientAreaAnimation, 0, (IntPtr)(enabled ? 1 : 0), SpifUpdateIniFile | SpifSendChange))
            throw new InvalidOperationException($"SPI_SETCLIENTAREAANIMATION failed ({Marshal.GetLastWin32Error()})");
    }

    private static void SetTransparency(bool enabled)
    {
        using (var key = Registry.CurrentUser.CreateSubKey(PersonalizeKey))
            key.SetValue("EnableTransparency", enabled ? 1 : 0, RegistryValueKind.DWord);
        Broadcast("ImmersiveColorSet");
    }

    /// <summary>Settings → Personalization → Colors → "Choose your default app mode" (apps only; the system mode is untouched).</summary>
    /// <param name="light">Light app mode when true, Dark when false.</param>
    private static void SetLightTheme(bool light)
    {
        using (var key = Registry.CurrentUser.CreateSubKey(PersonalizeKey))
            key.SetValue("AppsUseLightTheme", light ? 1 : 0, RegistryValueKind.DWord);
        Broadcast("ImmersiveColorSet");
        Thread.Sleep(1000);
    }

    private static void SetTextScale(int percent)
    {
        if (percent is < 100 or > 225) throw new ArgumentOutOfRangeException(nameof(percent), "text_scale must be 100–225");
        using (var key = Registry.CurrentUser.CreateSubKey(AccessibilityKey))
        {
            if (percent == 100) key.DeleteValue("TextScaleFactor", throwOnMissingValue: false);
            else key.SetValue("TextScaleFactor", percent, RegistryValueKind.DWord);
        }
        Broadcast("WindowMetrics");
    }

    private static void Broadcast(string area)
    {
        var text = Marshal.StringToHGlobalUni(area);
        try
        {
            SendMessageTimeout(HwndBroadcast, WmSettingChange, IntPtr.Zero, text, SmtoAbortIfHung, 2000, out _);
        }
        finally
        {
            Marshal.FreeHGlobal(text);
        }
    }

    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private const string AccessibilityKey = @"Software\Microsoft\Accessibility";
    private const uint SpiGetHighContrast = 0x0042, SpiSetHighContrast = 0x0043;
    private const uint SpiGetClientAreaAnimation = 0x1042, SpiSetClientAreaAnimation = 0x1043;
    private const uint SpifUpdateIniFile = 0x1, SpifSendChange = 0x2, HcfHighContrastOn = 0x1;
    private const uint WmSettingChange = 0x001A, SmtoAbortIfHung = 0x2;
    private static readonly IntPtr HwndBroadcast = new(0xffff);

    [StructLayout(LayoutKind.Sequential)]
    private struct HighContrast
    {
        public uint Size;
        public uint Flags;
        public IntPtr DefaultScheme;
    }

    [DllImport("user32.dll", EntryPoint = "SystemParametersInfoW", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint param, ref HighContrast value, uint winIni);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint param, ref bool value, uint winIni);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SystemParametersInfo(uint action, uint param, IntPtr value, uint winIni);

    [DllImport("user32.dll")]
    private static extern uint GetSysColor(int index);

    private const int ColorWindow = 5;

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);

    #endregion
}
