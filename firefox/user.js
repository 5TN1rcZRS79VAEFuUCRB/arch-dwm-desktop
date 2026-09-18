// Follow the system's dark preference everywhere, including the home page
// (Firefox's "automatic" doesn't resolve to dark under a bare startx session).
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);
user_pref("layout.css.prefers-color-scheme.content-override", 0);
// Scaling comes from the system DPI (Xft.dpi in ~/.Xresources). Do not also set
// layout.css.devPixelsPerPx here -- Firefox multiplies the two (2.25x).
user_pref("layout.css.devPixelsPerPx", "-1.0");
