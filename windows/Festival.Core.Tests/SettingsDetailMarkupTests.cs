using System.Text.RegularExpressions;
using System.Xml.Linq;
using Festival.Core.Domain;

namespace Festival.Core.Tests;

/// <summary>
/// Guards issue #371: wide Settings is a list/detail page. Every chevron row the Core list names exists in the page
/// markup with its tag and automation id, the empty detail shows the placeholder, and the row control follows
/// contrast themes like the rest of Settings (#214).
/// </summary>
public class SettingsDetailMarkupTests
{
    private static readonly string AppRoot =
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Festival.App");

    #region Helpers

    /// <summary>Loads a Festival.App XAML file.</summary>
    /// <param name="relative">Path under Festival.App.</param>
    /// <returns>The parsed document.</returns>
    private static XDocument Load(string relative) => XDocument.Load(Path.Combine(AppRoot, relative));

    /// <summary>Reads an attribute by local name.</summary>
    /// <param name="element">Element.</param>
    /// <param name="name">Attribute local name (for example <c>AutomationProperties.AutomationId</c>).</param>
    /// <returns>The value, or null.</returns>
    private static string? Attr(XElement element, string name) =>
        element.Attributes().FirstOrDefault(a => a.Name.LocalName == name)?.Value;

    /// <summary>Settings detail rows declared in the page.</summary>
    /// <returns>The <c>SettingsDetailRow</c> elements.</returns>
    private static List<XElement> Rows() =>
        Load(Path.Combine("Pages", "SettingsPage.xaml")).Descendants()
            .Where(e => e.Name.LocalName == "SettingsDetailRow").ToList();

    #endregion

    [Fact]
    public void EveryDetail_HasOneRow_WithItsTagAndAutomationId()
    {
        var rows = Rows();
        Assert.Equal(SettingsDetails.Items.Count, rows.Count);
        foreach (var item in SettingsDetails.Items)
        {
            var row = Assert.Single(rows, r => Attr(r, "Tag") == item.Detail.ToString());
            Assert.Equal(item.AutomationId, Attr(row, "AutomationProperties.AutomationId"));
            Assert.Equal("OnDetailRowClick", Attr(row, "Click"));
        }
    }

    [Fact]
    public void Rows_FollowPageOrder()
    {
        var tags = Rows().Select(r => Attr(r, "Tag")).ToList();
        Assert.Equal(SettingsDetails.Items.Select(i => i.Detail.ToString()), tags);
    }

    [Fact]
    public void Page_HasPlaceholderAndDetailHosts()
    {
        var ids = Load(Path.Combine("Pages", "SettingsPage.xaml")).Descendants()
            .Select(e => Attr(e, "AutomationProperties.AutomationId")).OfType<string>().ToHashSet();
        Assert.Contains("fst.settings.detail.placeholder.title", ids);
        Assert.Contains("fst.settings.detail.placeholder.message", ids);
        Assert.Contains("fst.settings.detail", ids);
        Assert.Contains("fst.settings.detail.title", ids);
    }

    [Fact]
    public void Row_FollowsContrastThemes()
    {
        var doc = Load(Path.Combine("Controls", "SettingsDetailRow.xaml"));
        var literals = doc.Descendants().SelectMany(e => e.Attributes())
            .Where(a => Regex.IsMatch(a.Value, "^#[0-9A-Fa-f]{6,8}$")).ToList();
        Assert.Empty(literals);
        var merged = doc.Descendants().Where(e => e.Name.LocalName == "ResourceDictionary")
            .Select(e => Attr(e, "Source")).OfType<string>().Select(Path.GetFileName).ToList();
        Assert.Contains("NavRowButtonResources.xaml", merged);
    }
}
