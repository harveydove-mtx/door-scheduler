# door-scheduler
Matrix Hardware Door Scheduler

## Product drawings (`drawings.html`)
Standalone page (no build, no server) that turns dimensions into a dimensioned line drawing.
Open `drawings.html` in a browser, pick a product type, fill in the dimensions, then export as SVG, PNG or print to PDF.
Drawings can be saved/loaded as JSON, and the last values for each type are remembered in the browser.

Templates offered: multipoint lock and multipoint handle (lever or pad on backplate). The butt hinge, bar pull handle and plate/backplate templates are built but hidden for now; set `SHOW_HIDDEN_TEMPLATES = true` in `drawings.html` to offer them again.
To add a new product type, add an entry to `TEMPLATES` in `drawings.html` (a list of input fields plus a `draw(values)` function).
