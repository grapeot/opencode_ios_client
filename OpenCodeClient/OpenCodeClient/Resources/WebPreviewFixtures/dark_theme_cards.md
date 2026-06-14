# Dark Theme Readability

This fixture is designed to surface dark-on-dark and light-on-light bugs. Every
element here should remain readable in **both** light and dark themes. The
renderer supplies theme variables; the content below only sets colors where a
card explicitly defines its own contrasting pair.

Ordinary body text should follow the theme foreground color and stay legible.

<style>
.theme-card {
  border-radius: 10px;
  padding: 14px 18px;
  margin: 12px 0;
  background-color: #263238;
  color: #eceff1;
  border: 1px solid #455a64;
}
.theme-card strong {
  color: #80cbc4;
}
</style>

<div class="theme-card">
  <strong>Self-contained card.</strong>
  This card sets both its background and its text color, so it is readable
  regardless of the surrounding theme. The accent word uses a tint that has
  contrast against the dark card background.
</div>

A fenced code block (must not be dark text on a dark background):

```javascript
function themeColor(mode) {
  // Returns the foreground color for the active theme.
  return mode === "dark" ? "#eceff1" : "#212121";
}
```

A table that should keep readable borders and text in both themes:

| Token            | Light value | Dark value |
| ---------------- | ----------- | ---------- |
| Background       | #ffffff     | #121212    |
| Foreground       | #212121     | #eceff1    |
| Accent           | #00695c     | #80cbc4    |

If any of the above becomes unreadable when the theme flips, the theming layer
has a contrast bug.
