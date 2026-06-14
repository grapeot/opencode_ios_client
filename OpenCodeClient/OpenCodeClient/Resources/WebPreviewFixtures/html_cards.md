# Status Cards

The cards below use an embedded `<style>` block. They must render as colored,
rounded cards with padding — not as plain text.

<style>
.card {
  border-radius: 12px;
  padding: 16px 20px;
  margin: 12px 0;
  font-family: -apple-system, system-ui, sans-serif;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
}
.card h3 {
  margin: 0 0 6px 0;
  font-size: 16px;
}
.card p {
  margin: 0;
  font-size: 14px;
  line-height: 1.4;
}
.card.confirmed {
  background-color: #1b5e20;
  color: #e8f5e9;
}
.card.blocked {
  background-color: #b71c1c;
  color: #ffebee;
}
.card.in-progress {
  background-color: #e65100;
  color: #fff3e0;
}
.card.neutral {
  background-color: #37474f;
  color: #eceff1;
}
</style>

<div class="card confirmed">
  <h3>Confirmed</h3>
  <p>Deployment to staging completed successfully. All smoke tests passed.</p>
</div>

<div class="card blocked">
  <h3>Blocked</h3>
  <p>Production release is blocked pending security review sign-off.</p>
</div>

<div class="card in-progress">
  <h3>In Progress</h3>
  <p>Migration of the legacy data store is 60% complete.</p>
</div>

<div class="card neutral">
  <h3>Notes</h3>
  <p>This card uses a neutral palette to confirm multiple variants coexist.</p>
</div>

The text above each card should sit inside a filled, rounded rectangle.
