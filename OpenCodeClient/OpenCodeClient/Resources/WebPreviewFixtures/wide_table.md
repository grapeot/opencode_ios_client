# Wide Table

The paragraph below should wrap normally and stay readable without horizontal
scrolling, even on a phone. Only the table beneath it should scroll sideways.

This intro text is intentionally a few sentences long so that it fills the
content width and demonstrates normal text reflow. It must not inherit the
table's overflow behavior; the table is the only element that should require a
horizontal swipe to see all of its columns.

| ID  | Name      | Region     | Status      | Owner    | Priority | Created     | Updated     | Tags          | Notes                  |
| --- | --------- | ---------- | ----------- | -------- | -------- | ----------- | ----------- | ------------- | ---------------------- |
| 001 | Orion     | us-east-1  | confirmed   | alice    | high     | 2026-01-04  | 2026-02-11  | infra,core    | Stable in production   |
| 002 | Lyra      | eu-west-2  | in-progress | bob      | medium   | 2026-01-18  | 2026-03-02  | data,etl      | Migration underway     |
| 003 | Draco     | ap-south-1 | blocked     | carol    | high     | 2026-02-01  | 2026-03-15  | security      | Awaiting review        |
| 004 | Vega      | us-west-2  | confirmed   | dave     | low      | 2026-02-09  | 2026-03-20  | ui,frontend   | Minor polish pending   |
| 005 | Cygnus    | eu-north-1 | in-progress | erin     | medium   | 2026-02-22  | 2026-04-01  | api,backend   | Rate limiting added    |
| 006 | Perseus   | sa-east-1  | confirmed   | frank    | high     | 2026-03-03  | 2026-04-12  | infra,scale   | Autoscaling verified   |

The table has ten columns; the first few should be visible while the rest
require scrolling horizontally within the table region only.
