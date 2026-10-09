# Column sort

Users sort the outline by clicking a column header. There is no Sort dropdown.

## Sub-features

- `header-click` — click Check / Type / Status / Latency to sort
- `indicator` — header shows the active sort direction
- `no-dropdown` — Sort is absent from the toolbar and View menu

## How to get to it (user POV)

- Click a table column header
- Click again to reverse

## Driving it with osascript

Preconditions: at least two checks in the table.

- Action: click the Check header. Result: rows reorder by title; a sort indicator appears on that column.
- Action: click again. Result: order reverses.

## Gotchas

- Group rows stay as group headers; sort applies inside groups when Group By is Tag or Kind.
- Manual drag order is available when no sort descriptor is set (clicking a header leaves that mode).
