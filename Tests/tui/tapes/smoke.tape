# Smoke test — verify KitchenSink starts and renders with ANSI renderer
Output Tests/tui/output/smoke.gif
Set Shell "bash"
Set FontSize 14
Set Width 120
Set Height 40
Set Padding 10

Type "OMNIUI_SMOKE_SECONDS=3 .build/debug/KitchenSink --notcurses"
Enter
Sleep 5s
