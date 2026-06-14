# Inline SVG Diagram

The diagram below is drawn with an inline `<svg>` element. It should render as a
simple three-step flowchart with boxes, connecting lines, and labels.

<svg viewBox="0 0 360 120" width="360" height="120" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Three step flowchart">
  <rect x="10" y="40" width="90" height="40" rx="6" fill="#1565c0" stroke="#0d47a1" stroke-width="2"/>
  <text x="55" y="65" font-size="13" fill="#ffffff" text-anchor="middle" font-family="sans-serif">Input</text>

  <line x1="100" y1="60" x2="135" y2="60" stroke="#555555" stroke-width="2"/>

  <rect x="135" y="40" width="90" height="40" rx="6" fill="#2e7d32" stroke="#1b5e20" stroke-width="2"/>
  <text x="180" y="65" font-size="13" fill="#ffffff" text-anchor="middle" font-family="sans-serif">Process</text>

  <line x1="225" y1="60" x2="260" y2="60" stroke="#555555" stroke-width="2"/>

  <rect x="260" y="40" width="90" height="40" rx="6" fill="#ef6c00" stroke="#e65100" stroke-width="2"/>
  <text x="305" y="65" font-size="13" fill="#ffffff" text-anchor="middle" font-family="sans-serif">Output</text>
</svg>

The flow is **Input -> Process -> Output**. If the SVG renders, inline vector
graphics are supported by the preview.
