"""Temporary CI probe for #533 bands-empty (removed before finishing)."""
import os, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "windows"))
import journey_exe  # noqa: E402

PS = r'''
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, PIDX)))
"window rect=$($win.Current.BoundingRectangle)"
foreach ($k in 'fst.player.bands','fst.player.bands.empty.duos','fst.player.bands.empty.trios','fst.player.bands.empty.quads') {
  $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $k)))
  "$k : count=$($all.Count)"
  foreach ($t in $all) {
  "  offscreen=$($t.Current.IsOffscreen) rect=$($t.Current.BoundingRectangle)"
  $w = [System.Windows.Automation.TreeWalker]::ControlViewWalker
  $p = $w.GetParent($t)
  while ($p) {
    $sp = $null
    if ($p.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$sp)) {
      $c = $sp.Current
      "     pane '$($p.Current.AutomationId)' vScrollable=$($c.VerticallyScrollable) vView=$($c.VerticalViewSize) vPct=$($c.VerticalScrollPercent) rect=$($p.Current.BoundingRectangle)"
    }
    $p = $w.GetParent($p)
  }
  }
}
$panes = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.OrCondition((New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Pane)), (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::List)))))
"first vertically scrollable panes:"
foreach ($p in $panes) { $sp = $null; if ($p.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$sp) -and $sp.Current.VerticallyScrollable) { "  '$($p.Current.AutomationId)' name='$($p.Current.Name)' rect=$($p.Current.BoundingRectangle)" } }
'''


def uiwin(*args):
    r = subprocess.run([sys.executable, str(REPO / "tools" / "windows" / "uiwin.py"), *args], capture_output=True, text=True, encoding="utf-8")
    print(f"$ uiwin {' '.join(args)[:200]}\n{r.stdout}\n{r.stderr}", flush=True)
    return r


def probe(pid, label):
    script = Path(tempfile.gettempdir()) / "probe533.ps1"
    script.write_text(PS.replace("PIDX", str(pid)), encoding="utf-8")
    r = subprocess.run(["powershell", "-NoProfile", "-File", str(script)], capture_output=True, text=True)
    print(f"--- probe {label}\n{r.stdout}\n{r.stderr}", flush=True)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    mock = subprocess.Popen([sys.executable, str(REPO / "tools" / "mock_service.py"), "--port", "18533"])
    time.sleep(4)
    settings = Path(tempfile.mkdtemp()) / "settings.json"
    r = uiwin("launch", str(journey_exe.DEBUG_EXE), "--arg=--base-url", "--arg=http://127.0.0.1:18533/", "--arg=--settings-path",
              f"--arg={settings}", "--preset", "portrait-tablet", "--arg=--route", "--arg=/player/fixture-player-2", "--arg=--anonymous")
    pid = next(int(l.split(":")[1].strip().rstrip(",")) for l in r.stdout.splitlines() if '"pid"' in l)
    for i, steps in enumerate(["waitfor:id=fst.player.overview@15; reveal:id=fst.player.bands@10",
                               "reveal:id=fst.player.bands.empty.duos@15",
                               "reveal:id=fst.player.bands.empty.trios@5",
                               "reveal:id=fst.player.bands.empty.quads@5"]):
        uiwin("drive", "--pid", str(pid), "--steps", f"{steps}; shot:{out / f'probe-{i}.png'}")
        probe(pid, steps)
    uiwin("close", "--pid", str(pid))
    mock.terminate()


main()
