using System.Xml.Linq;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #539 (pattern <c>settings-value-row</c> R1): the Service Info "Leaderboard Service State" row is the shared
/// measured-fit <c>SettingValueGrid</c> (title + state text as the label, process state as the value), not a
/// text-size-threshold grid laid out in code-behind.
/// </summary>
public class SettingsServiceStateRowMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Reads an attribute by local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Attribute local name.</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>The value grid that contains the state text.</summary>
    /// <returns>The <c>SettingValueGrid</c> element.</returns>
    private static XElement StateRow()
    {
        var doc = XDocument.Load(Path.Combine(AppRoot, "Pages", "SettingsPage.xaml"));
        var state = doc.Descendants().Single(e => Attr(e, "AutomationProperties.AutomationId") == "fst.settings.service-info.state");
        return state.Ancestors().First(e => e.Name.LocalName == "SettingValueGrid");
    }

    #endregion

    [Fact]
    public void StateRow_IsTheSharedValueGrid_LabelThenValue()
    {
        var children = StateRow().Elements().ToList();
        Assert.Equal(2, children.Count);
        var label = children[0].Elements().ToList();
        Assert.Equal("Leaderboard Service State", Attr(label[0], "Text"));
        Assert.Equal("fst.settings.service-info.state", Attr(label[1], "AutomationProperties.AutomationId"));
        var ids = children[1].Elements().Select(e => Attr(e, "AutomationProperties.AutomationId")).ToList();
        Assert.Equal(["fst.settings.service-info.process", "fst.settings.service-info.spinner"], ids);
    }

    [Fact]
    public void CodeBehind_NoLongerStacksByTextScale()
    {
        var code = File.ReadAllText(Path.Combine(AppRoot, "Pages", "SettingsPage.xaml.cs"));
        Assert.DoesNotContain("TextScaleFactor", code);
        Assert.DoesNotContain("Grid.SetRow", code);
    }

    [Fact]
    public void ValueGrid_FitsOnTheTitleOnly()
    {
        var code = File.ReadAllText(Path.Combine(AppRoot, "Controls", "SettingValueGrid.cs"));
        Assert.Contains("TitleWidth(Children[i])", code);
    }
}
