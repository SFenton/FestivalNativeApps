using System.Runtime.CompilerServices;

namespace Festival.App.Services;

#region Page state
/// <summary>
/// Keeps a pushed page's view model alive for its back-stack entry, keyed by the navigation parameter's reference
/// (Frame hands back the same route object on Back). Returning from a profile restores the page, switcher and metric
/// without a reload; entries disappear with their back-stack entries.
/// </summary>
/// <typeparam name="T">View model type.</typeparam>
internal static class LeaderboardsPageState<T> where T : class
{
    private static readonly ConditionalWeakTable<object, T> States = new();

    /// <summary>Returns the view model stored for this parameter, or creates and stores one.</summary>
    /// <param name="parameter">Navigation parameter (route object).</param>
    /// <param name="create">Factory for a first visit.</param>
    /// <param name="created">Whether a new model was created.</param>
    /// <returns>View model.</returns>
    public static T GetOrCreate(object parameter, Func<T> create, out bool created)
    {
        if (States.TryGetValue(parameter, out var existing))
        {
            created = false;
            return existing;
        }
        var model = create();
        States.AddOrUpdate(parameter, model);
        created = true;
        return model;
    }
}
#endregion
