"""Argument parsing and pure logic of ``tools/windows/uiwin.py``.

Covers step/selector/key parsing, presets, launch environment, perf
aggregation and task-status parsing without touching the desktop.
Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import tempfile
import unittest
from pathlib import Path

from tools.windows import uiwin as u


class SelectorAndKeyTests(unittest.TestCase):
    """UIA selectors and key combos."""

    def test_selectors(self):
        self.assertEqual(u.parse_selector("id=fst.songs.list"), {"kind": "id", "value": "fst.songs.list"})
        self.assertEqual(u.parse_selector("NAME=Refresh songs"), {"kind": "name", "value": "Refresh songs"})
        self.assertEqual(u.parse_selector(" 12, 34 "), {"kind": "xy", "x": 12, "y": 34})
        self.assertEqual(u.parse_selector("id=1&class=Button"), {"kind": "id", "value": "1", "class": "Button"})
        self.assertEqual(u.parse_selector("name=A&B&class=Edit"), {"kind": "name", "value": "A&B", "class": "Edit"})
        self.assertEqual(u.parse_selector("raw=a&class=b"), {"kind": "raw", "value": "a&class=b"})
        for bad in ("fst.x", "id=", "role=button"):
            with self.assertRaises(ValueError):
                u.parse_selector(bad)

    def test_keys(self):
        self.assertEqual(u.parse_keys("ctrl+shift+tab"), [0x11, 0x10, 0x09])
        self.assertEqual(u.parse_keys("alt+F4"), [0x12, 0x73])
        self.assertEqual(u.parse_keys("ctrl+l"), [0x11, ord("L")])
        with self.assertRaises(ValueError):
            u.parse_keys("ctrl+hyper")


class StepTests(unittest.TestCase):
    """Driver step expansion."""

    def test_selector_steps_with_timeout(self):
        step = u.parse_step("waitfor:id=fst.songs.list@10")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.songs.list"})
        self.assertEqual(step["timeout"], 10.0)
        self.assertNotIn("timeout", u.parse_step("invoke:id=fst.songs.refresh"))

    def test_reveal_takes_a_selector(self):
        step = u.parse_step("reveal:id=fst.history.view-all@3")
        self.assertEqual((step["verb"], step["selector"]["value"], step["timeout"]), ("reveal", "fst.history.view-all", 3.0))
        with self.assertRaises(ValueError):
            u.parse_step("reveal:5,6")

    def test_coordinates_only_for_clicks(self):
        self.assertEqual(u.parse_step("click:5,6")["selector"]["kind"], "xy")
        self.assertEqual(u.parse_step("hover:5,6")["selector"]["kind"], "xy")
        self.assertEqual(u.parse_step("hover:id=fst.songs.list")["selector"]["kind"], "id")
        with self.assertRaises(ValueError):
            u.parse_step("invoke:5,6")

    def test_key_scroll_wait(self):
        self.assertEqual(u.parse_step("key:enter")["vk"], [0x0D])
        self.assertEqual(u.parse_step("scroll:down")["amount"], -3)
        scroll = u.parse_step("scroll:id=fst.songs.list,-7")
        self.assertEqual((scroll["amount"], scroll["selector"]["value"]), (-7, "fst.songs.list"))
        self.assertEqual(u.parse_step("wait:2")["arg"], "2.0")
        with self.assertRaises(ValueError):
            u.parse_step("scroll:sideways")
        with self.assertRaises(ValueError):
            u.parse_step("wait:soon")

    def test_scrollto_uses_the_scroll_pattern_selector(self):
        step = u.parse_step("scrollto:id=fst.player.available,62.5")
        self.assertEqual((step["selector"]["value"], step["percent"]), ("fst.player.available", 62.5))
        self.assertEqual(u.parse_step("reveal:id=fst.player.percentiles.Solo_Guitar@10")["timeout"], 10.0)
        with self.assertRaises(ValueError):
            u.parse_step("reveal:5,6")
        for bad in ("scrollto:id=x", "scrollto:id=x,101", "scrollto:id=x,down", "scrollto:5,6,10", "scrollto:,50"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertnoscrollbar_takes_an_element_selector(self):
        step = u.parse_step("assertnoscrollbar:id=fst.paths.image-scroller")
        self.assertEqual((step["verb"], step["selector"]), ("assertnoscrollbar", {"kind": "id", "value": "fst.paths.image-scroller"}))
        for bad in ("assertnoscrollbar:5,6", "assertnoscrollbar:"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_paths_resize_and_errors(self):
        shot = u.parse_step("shot:out/a.png@screen")
        self.assertEqual(shot["mode"], "screen")
        self.assertTrue(Path(shot["arg"]).is_absolute())
        self.assertTrue(shot["arg"].endswith("a.png"))
        self.assertEqual(u.parse_step("resize:compact")["op"], u.PRESETS["compact"])
        for bad in ("fly:x", "click:", "resize:huge"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertstate(self):
        step = u.parse_step("assertstate:id=fst.instrument-selector.Solo_Guitar|toggle=On@3")
        self.assertEqual(step["verb"], "assertstate")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.instrument-selector.Solo_Guitar"})
        self.assertEqual((step["key"], step["value"], step["timeout"]), ("toggle", "on", 3.0))
        named = u.parse_step("assertstate:id=x.value|name=Selected: Pro Drums + Cymbals")
        self.assertEqual((named["key"], named["value"]), ("name", "Selected: Pro Drums + Cymbals"))
        self.assertNotIn("timeout", named)
        self.assertEqual(u.parse_step("assertstate:name=Lead|enabled=false")["value"], "false")
        selected = u.parse_step("assertstate:id=fst.quick-links.item.licenses|selected=True@4")
        self.assertEqual((selected["key"], selected["value"], selected["timeout"]), ("selected", "true", 4.0))
        top = u.parse_step("assertstate:id=fst.songs.list|scroll=0@5")
        self.assertEqual((top["key"], top["value"], top["timeout"]), ("scroll", "0", 5.0))
        self.assertEqual(u.parse_step("assertstate:id=x|scroll=-1")["value"], "-1")
        self.assertEqual(u.parse_step("assertstate:id=x|scroll=100")["value"], "100")
        role = u.parse_step("assertstate:id=fst.song-detail.preview-row.Solo_Guitar.rank-3|type=Text@5")
        self.assertEqual((role["key"], role["value"], role["timeout"]), ("type", "text", 5.0))
        self.assertEqual(u.parse_step("assertstate:id=x|invoke=False")["value"], "false")
        self.assertEqual(u.parse_step("assertstate:id=x|focusable=true")["value"], "true")
        # Issue #280: a combo box's current option keeps its case (Narrator reads "Instrument, combo box, Pro Bass").
        current = u.parse_step("assertstate:id=fst.paths.instrument.compact|value=Pro Bass@5")
        self.assertEqual((current["key"], current["value"], current["timeout"]), ("value", "Pro Bass", 5.0))
        # Issue #380: a raw-view demo's HelpText census keeps its case and may be a regex (`~`, `|` after the first).
        census = u.parse_step(r"assertstate:raw=fst.first-run.demo.songs-sort|help=~^controls=(?=.*\bRadioButtons\b)@15")
        self.assertEqual(census["selector"], {"kind": "raw", "value": "fst.first-run.demo.songs-sort"})
        self.assertEqual((census["key"], census["value"], census["timeout"]),
                         ("help", r"~^controls=(?=.*\bRadioButtons\b)", 15.0))
        for bad in ("assertstate:id=x", "assertstate:id=x|toggle", "assertstate:id=x|toggle=maybe", "assertstate:id=x|value=",
                    "assertstate:id=x|enabled=yes", "assertstate:id=x|color=red", "assertstate:@1,2|toggle=on",
                    "assertstate:id=x|name=", "assertstate:id=x|selected=on", "assertstate:id=x|scroll=top",
                    "assertstate:id=x|scroll=101", "assertstate:id=x|scroll=2.5", "assertstate:id=x|scroll=-2",
                    "assertstate:id=x|type=", "assertstate:id=x|invoke=yes", "assertstate:id=x|focusable=1"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)
    def test_assertstatus(self):
        step = u.parse_step("assertstatus:id=fst.shell.artwork-background|reduced-motion@20")
        self.assertEqual(step["verb"], "assertstatus")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.shell.artwork-background"})
        self.assertEqual(step["status"], "reduced-motion")
        self.assertEqual(step["timeout"], 20.0)
        plain = u.parse_step("assertstatus:name=Backdrop|no-art")
        self.assertEqual(plain["status"], "no-art")
        self.assertNotIn("timeout", plain)
        # Issue #258: a `~` regex status passes through to FstUia unchanged.
        regex = u.parse_step(r"assertstatus:id=fst.first-run.demo.songs-song-list|~^catalogue rotation=running swaps=[1-9]\d* swap=fade$@15")
        self.assertEqual(regex["status"], r"~^catalogue rotation=running swaps=[1-9]\d* swap=fade$")
        self.assertEqual(regex["timeout"], 15.0)
        for bad in ("assertstatus:id=x", "assertstatus:id=x|", "assertstatus:@1,2|on"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_foreground(self):
        # Issue #258: deactivate the app without covering it, then reactivate it.
        self.assertEqual(u.parse_step("foreground:off"), {"verb": "foreground", "arg": "off"})
        self.assertEqual(u.parse_step("foreground: ON")["arg"], "on")
        for bad in ("foreground:", "foreground:maybe", "foreground:id=x"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_listen_and_assertannounced(self):
        # Issue #269: record the app's UIA notifications (what Narrator speaks), then wait for one.
        self.assertEqual(u.parse_step("listen:Announcements"), {"verb": "listen", "arg": "announcements"})
        step = u.parse_step("assertannounced:Loading Lead Hard path@5")
        self.assertEqual((step["verb"], step["text"], step["timeout"]), ("assertannounced", "Loading Lead Hard path", 5.0))
        self.assertNotIn("timeout", u.parse_step("assertannounced:Lead Hard path image loaded"))
        regex = u.parse_step(r"assertannounced:~^Lead Expert path loaded, \d+ activations?$@2.5")
        self.assertEqual((regex["text"], regex["timeout"]), (r"~^Lead Expert path loaded, \d+ activations?$", 2.5))
        self.assertEqual(u.parse_step("assertannounced:mail@home")["text"], "mail@home")
        for bad in ("listen:", "listen:focus", "assertannounced:", "assertannounced:@5"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertannouncedcount(self):
        # Issue #275: a value announced once, not repeated by later reads.
        step = u.parse_step("assertannouncedcount:1|Phase. 1,310 attempted this pass · 70 | x")
        self.assertEqual((step["verb"], step["count"], step["text"]),
                         ("assertannouncedcount", 1, "Phase. 1,310 attempted this pass · 70 | x"))
        self.assertEqual(u.parse_step(r"assertannouncedcount:0|~^Loading")["count"], 0)
        for bad in ("assertannouncedcount:", "assertannouncedcount:1", "assertannouncedcount:x|text",
                    "assertannouncedcount:1|", "assertannouncedcount:-1|text"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertgap(self):
        step = u.parse_step("assertgap:id=fst.song-leaderboard.row.p-25|id=fst.song-leaderboard.page-first|4")
        self.assertEqual(step["verb"], "assertgap")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.song-leaderboard.row.p-25"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.song-leaderboard.page-first"})
        self.assertEqual(step["epx"], 4.0)
        self.assertEqual(u.parse_step("assertgap:name=A|name=B|2.5")["epx"], 2.5)
        for bad in ("assertgap:id=a|id=b", "assertgap:id=a|id=b|x", "assertgap:id=a|4", "assertgap:1,2|id=b|4",
                    "assertgap:id=a|id=b|-4"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertpaint(self):
        step = u.parse_step("assertpaint:id=fst.notifications.row.x|fill:L8,M0=#162133~4|L4,M-10,L5,M10=#1e2a3a"
                            "|R25,M-24!=@fill~40|C-0.5,B2.5,C20,B-3!=@fill")
        self.assertEqual(step["verb"], "assertpaint")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.notifications.row.x"})
        fill, stroke, dot, gap = step["probes"]
        self.assertEqual(fill, {"text": "fill:L8,M0=#162133~4", "x": {"edge": "L", "off": 8.0},
                                "y": {"edge": "M", "off": 0.0}, "op": "=", "color": "#162133", "tol": 4, "name": "fill"})
        self.assertEqual((stroke["x2"], stroke["y2"], stroke["color"], stroke["tol"]),
                         ({"edge": "L", "off": 5.0}, {"edge": "M", "off": 10.0}, "#1E2A3A", 16))
        self.assertEqual((dot["op"], dot["ref"], dot["x"]), ("!=", "fill", {"edge": "R", "off": 25.0}))
        self.assertNotIn("color", dot)
        self.assertEqual((gap["x"]["off"], gap["y2"]), (-0.5, {"edge": "B", "off": -3.0}))
        sample = u.parse_step("assertpaint:raw=fst.art|art:L47,M0")["probes"][0]
        self.assertEqual((sample["name"], "op" in sample), ("art", False))
        for bad in ("assertpaint:id=a", "assertpaint:id=a|", "assertpaint:1,2|a:L1,T1", "assertpaint:id=a|L1,T1",
                    "assertpaint:id=a|L1,T1,L2,T2", "assertpaint:id=a|a:L1,T1,L2,T2=#000000",
                    "assertpaint:id=a|X1,T1=#000000", "assertpaint:id=a|L1,T1=#00000", "assertpaint:id=a|L1,T1=@nope",
                    "assertpaint:id=a|L1,T1=#000000~256", "assertpaint:id=a|L1,T1=#000000||"):
            with self.assertRaises(ValueError, msg=bad):
                u.parse_step(bad)

    def test_parse_probe_names_are_ordered(self):
        names: set[str] = set()
        self.assertEqual(u.parse_probe("a:L1,T1", names)["name"], "a")
        self.assertEqual(names, {"a"})
        self.assertEqual(u.parse_probe("L2,T2=@a~3", names)["ref"], "a")
        with self.assertRaises(ValueError):
            u.parse_probe("L2,T2=@b", names)

    def test_assertbold(self):
        step = u.parse_step("assertbold:id=fst.notifications.row.x|Lead| Fixture Pulse |201,234")
        self.assertEqual(step["verb"], "assertbold")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.notifications.row.x"})
        self.assertEqual(step["runs"], ["Lead", "Fixture Pulse", "201,234"])
        self.assertEqual(u.parse_step("assertbold:id=a|")["runs"], [])
        for bad in ("assertbold:id=a", "assertbold:1,2|Lead"):
            with self.assertRaises(ValueError, msg=bad):
                u.parse_step(bad)

    def test_span(self):
        step = u.parse_step("markspan:id=fst.history.instrument.group|id=fst.history.sort.open|card")
        self.assertEqual(step["verb"], "markspan")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.history.instrument.group"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.history.sort.open"})
        self.assertEqual(step["name"], "card")
        self.assertEqual(u.parse_step("assertspan:name=A|name=B|card-2")["name"], "card-2")
        for bad in ("assertspan:id=a|id=b", "assertspan:id=a|id=b|", "markspan:id=a|card", "assertspan:1,2|id=b|c",
                    "markspan:id=a|id=b|bad name"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_film(self):
        start, stop = u.parse_step("film:out/fade"), u.parse_step("filmstop:out/fade")
        self.assertEqual((start["verb"], stop["verb"]), ("film", "filmstop"))
        self.assertEqual(start["arg"], stop["arg"])
        self.assertTrue(Path(start["arg"]).is_absolute())
        with self.assertRaises(ValueError):
            u.parse_step("filmstop:")

    def test_keys_sequence(self):
        step = u.parse_step("keys:left space shift+tab")
        self.assertEqual(step["seq"], [[0x25], [0x20], [0x10, 0x09]])
        with self.assertRaises(ValueError):
            u.parse_step("keys:left nosuchkey")

    def test_pin_and_assertpinned(self):
        pin = u.parse_step("pin:id=fst.songs.sort@5")
        self.assertEqual(pin["verb"], "pin")
        self.assertEqual(pin["selector"], {"kind": "id", "value": "fst.songs.sort"})
        self.assertEqual(pin["timeout"], 5.0)
        check = u.parse_step("assertpinned:id=fst.songs.sort")
        self.assertEqual(check["verb"], "assertpinned")
        self.assertEqual(check["selector"], pin["selector"])
        for bad in ("pin:10,20", "assertpinned:10,20", "pin:", "assertpinned:sort"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertmarquee(self):
        moving = u.parse_step("assertmarquee:id=fst.song-detail.title|moving|44")
        self.assertEqual(moving["selector"], {"kind": "id", "value": "fst.song-detail.title"})
        self.assertEqual((moving["mode"], moving["epx"]), ("moving", 44.0))
        still = u.parse_step("assertmarquee:raw=fst.song-band-leaderboard.song-title|static|28.5")
        self.assertEqual(still["selector"]["kind"], "raw")
        self.assertEqual((still["mode"], still["epx"]), ("static", 28.5))
        wrapped = u.parse_step("assertmarquee:id=fst.song-detail.title|wrapped|90")
        self.assertEqual((wrapped["mode"], wrapped["epx"]), ("wrapped", 90.0))
        fits = u.parse_step("assertmarquee:id=fst.song-detail.artist|fits|32")
        self.assertEqual((fits["mode"], fits["epx"]), ("fits", 32.0))
        for bad in ("assertmarquee:id=x", "assertmarquee:id=x|moving", "assertmarquee:id=x|wrap|44",
                    "assertmarquee:id=x|static|tall", "assertmarquee:10,20|moving|44"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertmarqueesync(self):
        step = u.parse_step("assertmarqueesync:id=fst.song-detail.title|id=fst.song-detail.artist")
        self.assertEqual(step["verb"], "assertmarqueesync")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.song-detail.title"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.song-detail.artist"})
        for bad in ("assertmarqueesync:id=x", "assertmarqueesync:10,20|id=y"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertinset(self):
        step = u.parse_step("assertinset:name=Show Instruments&class=TextBlock|id=fst.settings|40")
        self.assertEqual(step["verb"], "assertinset")
        self.assertEqual(step["selector"], {"kind": "name", "value": "Show Instruments", "class": "TextBlock"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.settings"})
        self.assertEqual(step["epx"], 40.0)
        for bad in ("assertinset:id=a|id=b", "assertinset:id=a|id=b|-2", "assertinset:id=a|1,2|32"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_scrollinset(self):
        step = u.parse_step("scrollinset:id=fst.suggestions.category.x|id=fst.suggestions.list|8")
        self.assertEqual(step["verb"], "scrollinset")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.suggestions.category.x"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.suggestions.list"})
        self.assertEqual(step["epx"], 8.0)
        for bad in ("scrollinset:id=a|id=b", "scrollinset:id=a|id=b|-8", "scrollinset:id=a|1,2|8",
                    "scrollinset:id=a|id=b|0"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertsize(self):
        step = u.parse_step("assertsize:id=fst.global-search.open|40x40")
        self.assertEqual(step["verb"], "assertsize")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.global-search.open"})
        self.assertEqual((step["width"], step["height"]), (40.0, 40.0))
        self.assertEqual(u.parse_step("assertsize:id=fst.quick-links.open|0x40.5")["height"], 40.5)
        for bad in ("assertsize:id=a", "assertsize:id=a|40", "assertsize:id=a|-1x40", "assertsize:10,20|40x40"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertat(self):
        step = u.parse_step("assertat:id=fst.shell.profile|0,-18.5")
        self.assertEqual(step["verb"], "assertat")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.shell.profile"})
        self.assertEqual((step["dx"], step["dy"]), (0.0, -18.5))
        self.assertEqual(u.parse_step("assertat:id=a| 12 , 3 ")["dx"], 12.0)
        for bad in ("assertat:id=a", "assertat:id=a|1", "assertat:id=a|x,1", "assertat:10,20|0,0"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_tapat_and_clickat(self):
        for verb in ("tapat", "clickat"):
            step = u.parse_step(f"{verb}:id=fst.shell.profile|0,18.5")
            self.assertEqual(step["verb"], verb)
            self.assertEqual(step["selector"], {"kind": "id", "value": "fst.shell.profile"})
            self.assertEqual((step["dx"], step["dy"]), (0.0, 18.5))
            for bad in (f"{verb}:id=a", f"{verb}:id=a|1", f"{verb}:10,20|0,0"):
                with self.assertRaises(ValueError):
                    u.parse_step(bad)

    def test_assertapart(self):
        step = u.parse_step("assertapart:id=fst.songs.sort|id=fst.songs.filter")
        self.assertEqual(step["verb"], "assertapart")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.songs.sort"})
        self.assertEqual(step["other"], {"kind": "id", "value": "fst.songs.filter"})
        with self.assertRaises(ValueError):
            u.parse_step("assertapart:id=fst.songs.sort")

    def test_narrate(self):
        step = u.parse_step("narrate:id=fst.shell.titlebar@10")
        self.assertEqual(step["verb"], "narrate")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.shell.titlebar"})
        self.assertEqual(step["timeout"], 10.0)
        with self.assertRaises(ValueError):
            u.parse_step("narrate:10,20")

    def test_assertread(self):
        step = u.parse_step("assertread:id=fst.shell.profile|Select a player profile, button@8")
        self.assertEqual(step["verb"], "assertread")
        self.assertEqual(step["selector"], {"kind": "id", "value": "fst.shell.profile"})
        self.assertEqual(step["text"], "Select a player profile, button")
        self.assertEqual(step["timeout"], 8.0)
        regex = u.parse_step("assertread:id=fst.songs.sort|~^Sort Songs, button, collapsed")
        self.assertEqual(regex["text"], "~^Sort Songs, button, collapsed")
        self.assertNotIn("timeout", regex)
        for bad in ("assertread:id=a", "assertread:id=a| ", "assertread:10,20|x"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertorder(self):
        step = u.parse_step("assertorder:id=fst.global-search.open|id=fst.shell.notifications|id=fst.shell.profile@6")
        self.assertEqual(step["verb"], "assertorder")
        self.assertEqual([s["value"] for s in step["selectors"]],
                         ["fst.global-search.open", "fst.shell.notifications", "fst.shell.profile"])
        self.assertEqual(step["timeout"], 6.0)
        self.assertNotIn("timeout", u.parse_step("assertorder:id=a|name=b"))
        for bad in ("assertorder:id=a", "assertorder:id=a||id=b", "assertorder:id=a|1,2"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_window_state_presets(self):
        self.assertEqual(u.preset_op("minimized"), {"kind": "minimize"})
        self.assertEqual(u.preset_op("restored"), {"kind": "restore"})

    def test_parse_steps(self):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "s.txt"
            script.write_text("# comment\nkey:tab\n\n")
            self.assertEqual(u.parse_steps("wait:1;", str(script)), ["key:tab", "wait:1"])
        with self.assertRaises(ValueError):
            u.parse_steps(None, None)


class PresetTests(unittest.TestCase):
    """Window presets and clamp reporting."""

    def test_required_presets(self):
        self.assertEqual(u.preset_op("compact"), {"kind": "size", "width": 500, "height": 800})
        self.assertEqual(u.preset_op("medium"), {"kind": "size", "width": 900, "height": 700})
        self.assertEqual(u.preset_op("wide"), {"kind": "size", "width": 1440, "height": 900})
        self.assertEqual(u.preset_op("portrait-tablet"),
                         {"kind": "size", "width": 800, "height": 1280})
        self.assertEqual(u.preset_op("full-screen"), {"kind": "fullscreen"})
        self.assertEqual(u.preset_op("snap-left"), {"kind": "snap-left"})
        self.assertEqual(u.preset_op("snap-right"), {"kind": "snap-right"})
        self.assertEqual(u.preset_op("1024x768"), {"kind": "size", "width": 1024, "height": 768})
        with self.assertRaises(ValueError):
            u.preset_op("gigantic")

    def test_preset_op_is_a_copy(self):
        u.preset_op("compact")["width"] = 1
        self.assertEqual(u.PRESETS["compact"]["width"], 500)

    def test_clamp_warning(self):
        op = u.preset_op("portrait-tablet")
        self.assertIsNone(u.clamp_warning(op, {"bounds_epx": [800, 1279]}))
        self.assertIn("clamped", u.clamp_warning(op, {"bounds_epx": [800, 1392]}))
        self.assertIsNone(u.clamp_warning(u.preset_op("snap-left"), {}))


class LaunchEnvTests(unittest.TestCase):
    """Debug environment mirrors the Apple/Android names."""

    def test_env(self):
        env = u.launch_env("songs", "player:1", ["FST_DEBUG_DRAWER=1"])
        self.assertEqual(env, {"FST_DEBUG_TAB": "songs", "FST_DEBUG_ROUTE": "player:1",
                               "FST_DEBUG_DRAWER": "1"})
        with self.assertRaises(ValueError):
            u.launch_env(None, None, ["broken"])

    def test_automation_marks_only_repo_publishes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            publish = root / "artifacts" / "app" / "Release-aot"
            publish.mkdir(parents=True)
            exe = publish / "FestivalScoreTracker.exe"
            original = u.ARTIFACTS_ROOT
            u.ARTIFACTS_ROOT = root / "artifacts"
            try:
                env: dict[str, str] = {}
                self.assertIsNone(u.prepare_automation(exe, env))
                self.assertEqual(env["FST_AUTOMATION"], "1")
                self.assertTrue((publish / u.AUTOMATION_MARKER).exists())
                elsewhere = root / "installed" / "FestivalScoreTracker.exe"
                self.assertIn("no fst-automation.marker", u.prepare_automation(elsewhere, {}))
                self.assertFalse((elsewhere.parent / u.AUTOMATION_MARKER).exists())
                debug = root / "bin" / "x64" / "Debug" / "FestivalScoreTracker.exe"
                self.assertIsNone(u.prepare_automation(debug, {}))
                opted_out = {"FST_AUTOMATION": "0"}
                self.assertIsNone(u.prepare_automation(elsewhere, opted_out))
                self.assertEqual(opted_out, {"FST_AUTOMATION": "0"})
            finally:
                u.ARTIFACTS_ROOT = original


class PerfTests(unittest.TestCase):
    """Counter paths, aggregation and PresentMon summaries."""

    def test_counter_paths(self):
        paths = u.counter_paths("Festival.App", 42)
        self.assertEqual(paths["cpu_percent"], r"\Process V2(Festival.App:42)\% Processor Time")
        self.assertIn("pid_42_*", paths["gpu_percent"])

    def test_summarize(self):
        self.assertEqual(u.summarize([]), {"mean": 0.0, "max": 0.0, "p95": 0.0, "samples": 0})
        summary = u.summarize([float(v) for v in range(1, 21)])
        self.assertEqual((summary["mean"], summary["max"], summary["p95"]), (10.5, 20.0, 19.0))

    def test_aggregate_counters_normalises_units(self):
        paths = u.counter_paths("app", 7)
        tick = {
            r"\process v2(app:7)\% processor time": 160.0,
            r"\process v2(app:7)\working set - private": 64 * 1024 * 1024,
            r"\gpu engine(pid_7_luid_0x1_phys_0_eng_0_engtype_3d)\utilization percentage": 30.0,
            r"\gpu engine(pid_7_luid_0x1_phys_0_eng_1_engtype_copy)\utilization percentage": 5.0,
            r"\gpu engine(pid_77_luid_0x1_phys_0_eng_0_engtype_3d)\utilization percentage": 99.0,
        }
        result = u.aggregate_counters([tick], paths, cpu_count=16)
        self.assertEqual(result["cpu_percent"]["mean"], 10.0)
        self.assertEqual(result["working_set_private_mb"]["mean"], 64.0)
        self.assertEqual(result["gpu_percent"]["mean"], 35.0)
        self.assertEqual(result["gpu_dedicated_mb"]["samples"], 0)

    def test_frame_stats(self):
        csv_v2 = "Application,FrameTime\napp,10\napp,20\napp,NA\n"
        stats = u.frame_stats(csv_v2)
        self.assertEqual(stats["frames"], 2)
        self.assertEqual(stats["fps_mean"], 66.7)
        self.assertEqual(u.frame_stats("Application,MsBetweenPresents\napp,5\n")["frames"], 1)
        self.assertEqual(u.frame_stats("Application,Other\napp,1\n"), {})
        self.assertEqual(u.frame_stats(""), {})


class TaskAndParserTests(unittest.TestCase):
    """Scheduled-task status parsing and CLI wiring."""

    def test_task_status(self):
        self.assertEqual(u.task_status('"\\FST_UiWin_x","N/A","Running"\r\n'), "Running")
        self.assertEqual(u.task_status('"\\FST_UiWin_x","9/28/2026 11:59:00 PM","Ready"'), "Ready")
        self.assertEqual(u.task_status(""), "")

    def test_parser(self):
        parser = u.build_parser()
        launch = parser.parse_args(["launch", "app.exe", "--tab", "songs", "--preset", "compact",
                                    "--extra", "K=V", "--arg=--flag"])
        self.assertEqual((launch.preset, launch.extra, launch.arg), ("compact", ["K=V"], ["--flag"]))
        self.assertIs(launch.func, u.cmd_launch)
        self.assertEqual((launch.steps, launch.steps_file), (None, None))
        held = parser.parse_args(["launch", "app.exe", "--steps", "wait:1; tree:t.txt"])
        self.assertEqual(held.steps, "wait:1; tree:t.txt")
        shot = parser.parse_args(["shot", "a.png", "--pid", "5", "--mode", "screen"])
        self.assertEqual((shot.pid, shot.mode, shot.hold), (5, "screen", 300.0))
        perf = parser.parse_args(["perf-sample", "--process", "Festival.App", "--presentmon"])
        self.assertEqual((perf.process, perf.seconds, perf.presentmon), ("Festival.App", 10, True))
        with self.assertRaises(SystemExit):
            parser.parse_args(["shot", "a.png", "--pid", "5", "--process", "x"])
        with self.assertRaises(SystemExit):
            parser.parse_args(["shot", "a.png", "--mode", "gdi"])

    def test_front_and_isolate_flags(self):
        parser = u.build_parser()
        front = parser.parse_args(["front", "--isolate"])
        self.assertIs(front.func, u.cmd_front)
        self.assertTrue(front.isolate)
        drive = parser.parse_args(["drive", "--steps", "wait:1", "--isolate", "--pid", "9"])
        self.assertEqual((drive.isolate, drive.pid), (True, 9))
        self.assertFalse(parser.parse_args(["tree"]).isolate)


class OcclusionRobustnessTests(unittest.TestCase):
    """Regression: other lanes' windows covering the target (foreground/isolate) and MSYS step paths."""

    def test_target_request(self):
        self.assertEqual(u.target_request(5, None, {"pid": 1}), {"pid": 5})
        self.assertEqual(u.target_request(None, "App", None), {"process": "App"})
        self.assertEqual(u.target_request(None, None, {"pid": 7}, isolate=True),
                         {"pid": 7, "isolate": True})
        for last in (None, {}, {"pid": 0}):
            with self.assertRaises(ValueError):
                u.target_request(None, None, last)

    def test_native_path(self):
        if u.os.name != "nt":
            self.skipTest("MSYS translation is Windows-only")
        self.assertEqual(u.native_path("/c/Users/me/a.png"), "C:/Users/me/a.png")
        self.assertEqual(u.native_path("/d"), "D:/")
        for unchanged in ("C:/x.png", "out/a.png", "/tmp2/a.png", r"C:\x\y.png"):
            self.assertEqual(u.native_path(unchanged), unchanged)
        shot = u.parse_step("shot:/c/Temp/fst/a.png")
        self.assertTrue(shot["arg"].upper().startswith("C:\\TEMP\\FST"), shot["arg"])

    def test_driver_foregrounds_before_input_steps(self):
        # The driver's contract lives in C#; guard that every real-input verb is foregrounded and that
        # isolation is restored when the request ends.
        source = (u.DRIVER_DIR / "Program.cs").read_text(encoding="utf-8")
        verbs = source.split("InputVerbs = [", 1)[1].split("]", 1)[0]
        for verb in ("click", "rightclick", "hover", "type", "key", "scroll"):
            self.assertIn(f'"{verb}"', verbs)
        self.assertIn("RestoreIsolated();", source.split("finally", 1)[1][:200])
        self.assertIn('"front" => Front(', source)


if __name__ == "__main__":
    unittest.main()
