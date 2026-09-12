# Web UI Design

## Purpose and status

AI Fitness is a personal training review and analysis tool. Cycling review is
its first detailed design reference: find a workout, import a FIT file, review
the activity, and open an individual metric for deeper analysis.

Desktop Web is the primary experience. Design, implement and validate desktop
and mobile Web together in each feature slice, sharing terminology, content,
page relationships and data semantics. Use desktop space for readable analysis
and map/chart comparison; adapt the same workflow to a touch-friendly, mostly
single-column mobile layout. Desktop priority determines design tradeoffs; mobile
acceptance remains part of the same feature.

This document owns the Web visual and interaction design. Page descriptions are
design targets, not an implementation checklist for the current task. The current
Web app is a synthetic training-review demo implementing a subset of these
design targets; connecting it to the implemented backend authentication and
manual Workout handlers remains future work. Source code and
manifests establish available capabilities. The numerical values below are working design defaults to validate
in real layouts, rather than individually approved pixel-level requirements.

## Visual language

Use a light, native-feeling interface: pale gray background, white content
surfaces, dark text, system fonts and restrained metric colors. Use the
**AI Fitness** wordmark initially. Interface labels are Simplified Chinese;
units retain their conventional symbols, such as bpm, W, rpm and km.

Create hierarchy through typography, spacing and subtle separators. Use one
level of content cards. A metric preview contains its title, one primary number
with unit and statistic label, then a chart spanning the available card width.
Analysis-page section headings sit above their content surfaces. Multiple
statistics use aligned label/value rows or a small group that can wrap vertically.
Numbers use tabular figures and consistent unit spacing.

Use the [Tabler Icons](https://tabler.io/icons) outline family for sport and
interface symbols, with rounded strokes and a shared 24-unit grid. The current
stroke weight is 1.8; icons inherit text color and keep their existing contextual
sizes. Sport icons use the blue accent on a pale background. Visible labels carry
the meaning; accompanying icons are decorative for assistive technology.

Give the current task room: previews communicate overall shape; a dedicated
analysis page gives the main chart visual priority. Content grows and scrolls at
readable sizes. Related detail is accessible through the metric page. A workout
overview is one continuous page, with direct links to full analysis.

Colors identify metrics, while labels, legends and line styles explain meaning.
Heart-rate red identifies heart rate; an alert needs its own explicit meaning.
Use a single-color line by default. Zone colors have named, defined ranges.
Load values show their method and unit; progress visuals require a defined target.

### Color defaults

| Role                              | Value                 |
| --------------------------------- | --------------------- |
| Page background / content surface | `#F4F4F8` / `#FFFFFF` |
| Primary / secondary text          | `#171923` / `#606672` |
| Decorative separator              | `#E6E8EE`             |
| Interactive accent                | `#1769D2`             |
| Heart rate                        | `#D43A4A`             |
| Power                             | `#7350C7`             |
| Cadence / speed                   | `#9A6300` / `#1769D2` |
| Elevation / balance               | `#586B63` / `#147D86` |

Use these as starting values and verify actual backgrounds, opacity and states.
Project targets are at least 4.5:1 for body text and 3:1 for essential graphical
marks and control boundaries. Decorative separators have a supporting role.
Necessary information remains available through text as well as color.

### Typography and spacing defaults

Web values are CSS pixels; typography entries are font size / line height.
System fonts include a Chinese fallback and support browser text enlargement.

| Element                   | Desktop                 | Mobile                         |
| ------------------------- | ----------------------- | ------------------------------ |
| Page title                | 30 / 40                 | 28 / 36                        |
| Analysis section title    | 22 / 30                 | 22 / 30                        |
| Card title                | 17 / 24                 | 18 / 26                        |
| Body and settings         | 16 / 24                 | 17 / 26                        |
| Secondary text            | 14 / 21                 | 15 / 22                        |
| Chart axes and legends    | 13 / 18                 | 13 / 18                        |
| Primary metric            | 28–32 / 36–40           | 28–32 / 36–40                  |
| Units                     | 14–15 / 21–22           | 15 / 22                        |
| Page horizontal padding   | 32; 24 when constrained | 20; 16 on narrow screens       |
| Card padding              | 20–24                   | 16–20                          |
| Card gap / section gap    | 20–24 / 32              | 16 / 28–32                     |
| Card radius               | 16–20                   | 20; up to 24 for larger groups |
| Preview plot height       | 100–140                 | 88–120                         |
| Main analysis plot height | 300–380                 | 240–300                        |

Plot height excludes titles, summaries, axes and legends. Card height follows its
content. Enlarged text wraps and increases height while preserving chart area.

## Responsive layout and navigation

### Desktop baseline

Start at **1440 × 900**, and check **1280 × 800** and **1920 × 1080**. Use a left
sidebar, a short breadcrumb and a main content region. Settings belong at the
bottom of the sidebar. Present destinations as they become usable.

The workout overview begins with activity identity, distance and a clearly
labeled duration. Below it, use a wide chart column and a narrower route-map
column. Stack power, heart rate, cadence, speed and elevation previews in the
main column. The map shows the complete route and links to route analysis;
brief notes may follow it. Sources and processing details sit later in the page.

| Layout parameter                  | Working default                                                       |
| --------------------------------- | --------------------------------------------------------------------- |
| Expanded sidebar                  | 208                                                                   |
| Compact navigation                | 72-wide icon rail with accessible labels, or a drawer                 |
| Main content maximum width        | 1200, centered on wider screens                                       |
| Chart column / map column minimum | 600 / 300                                                             |
| Column gap                        | 24                                                                    |
| Two-column threshold              | At least 924 of available content width                               |
| Example at 1440                   | 208 sidebar + 64 outer padding + 1168 content; columns 784 + 24 + 360 |
| Overview map height               | 260–320 initially, adjusted for route and window shape                |

Title, summary and grid share their left edge. The map aligns with the first
chart card at the top. Each module stays inside the main grid and uses its
natural height. Without GPS, use the available content region for the charts.
Map stickiness is an optional local improvement when it helps comparison and
fits the viewport without covering content.

Full metric analysis uses a dedicated page with a wide main chart. Related
statistics and methods may sit alongside each other when readable. Optional
future metric comparison should favor stacked charts with a shared time cursor;
an overlay needs explicit units, axes and legends.

### Mobile and intermediate widths

Use **393 × 852** as the main mobile browser test viewport, with **375** and
**430** widths and a **320** reflow check. Check **768** and **1024** for navigation
collapse and single-column reflow. These are test viewports, not fixed page sizes.
Actual browser chrome and safe areas determine usable space. The main page
reflows within the viewport; genuinely two-dimensional maps and tables can use
their own contained interaction or scrolling regions.

At widths below the two-column content threshold, collapse navigation and keep
readable text with one main content column. Mobile uses a global bottom bar once
multiple destinations exist; full-screen map/chart views can temporarily hide
it. Top navigation provides back, title and relevant actions. Reserve bottom-bar
height and safe-area padding so the last item remains reachable.

In the mobile overview, place activity identity, distance and duration first,
then a route preview around 200–220 high, then full-width metric previews. The
first screen shows as much as naturally fits. Independent charts remain stacked;
a pair of summary numbers may share a row and wrap when needed. On wide screens,
the map moves beside the chart column. Keep DOM, keyboard and visual reading
orders coherent for each layout.

### Page relationships

| Destination      | Relationship                                                                |
| ---------------- | --------------------------------------------------------------------------- |
| Training list    | Find activities and start a FIT import                                      |
| Workout overview | Continuous summary with links to each available analysis                    |
| Metric analysis  | Full statistics, chart, related analysis and method/source details          |
| Route analysis   | Large map with linked time/elevation controls                               |
| Source details   | Import result, recorded source, processing provenance and relevant settings |
| Device settings  | Data and devices → device → input coordinate interpretation                 |

Example future routes are `/workouts`, `/workouts/:id`,
`/workouts/:id/metrics/heart-rate`, `/workouts/:id/route` and
`/settings/devices/:id`. They describe page relationships, not existing routes or
backend endpoints. Detail pages support direct navigation, refresh and browser
back. Returning restores scroll position and focus. Short explanations and small
choices can use a panel; complete analysis has its own page.

## Workout review content

### List and import

Use date-grouped activity rows with sport, title, date, distance and duration.
Sport is a filter within training. Desktop has a visible import button and, when
implemented, file drop support; mobile has a visible add/import action. An empty
list explains its state and offers import.

Show selected filenames and counts, with limits supplied by the service. Use
byte progress for upload when measurable and a named processing state otherwise.
When one file completes, open its activity if the user is still waiting on that
flow. If they have moved elsewhere, use a non-blocking completion notification.
Batch imports show per-file success, duplicate and failure outcomes. A duplicate
links to the existing record; retry identity comes from the backend import policy.
Different source files remain separate records under the current no-fusion policy.
Partial success keeps usable activity data accessible; errors offer retry or a
replacement file using understandable messages.

### Overview

Use this content order, adapted to the desktop map column above. Availability
controls which modules appear; errors and pending work have explicit states.

| Content                                      | Preview and destination                                                          |
| -------------------------------------------- | -------------------------------------------------------------------------------- |
| Activity header                              | Sport, name, date, distance, duration; edit title/notes through relevant actions |
| Route                                        | Complete route, start/end and route-analysis link                                |
| Power, heart rate, cadence, speed, elevation | One main statistic and one full-width preview each; link to metric analysis      |
| Training load                                | A named, implemented load measure; link to method and detail                     |
| Laps and splits                              | Count or short summary; link to per-lap results                                  |
| Cycling dynamics                             | Discoverable entry for available balance, smoothness and torque effectiveness    |
| AI analysis                                  | Existing summary or a user-initiated analysis action when supported              |
| Notes and sources                            | User content, recorded origin and import/processing status                       |

The header defaults to distance and moving duration when the service provides
that defined statistic. Label any available alternative duration accurately.
Indoor workouts can use duration alone. Preview statistic labels are explicit,
including a non-zero average when applicable. A summary without samples gets a
numeric entry labeled accordingly. The whole metric preview is a focusable page
link with visible hover, focus and press states. Mobile previews preserve normal
vertical scrolling; sample selection belongs to the analysis view.

### Metric analysis

Use a shared reading pattern: activity context → key statistics → main chart →
zones/distribution → related analysis → method and sources. Related available
content continues down the page. Heart rate is the first detailed reference:
average and maximum, one bpm time-series chart, then configured zones with range,
duration and share of valid time. Missing zone configuration leaves the main
chart usable and explains why zone results are unavailable. Post-exercise heart
rate appears only with appropriate post-end samples and a supported method.

| Topic            | Content and prerequisites                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Power            | Average, maximum and time series; normalized power, intensity and best-duration means require supported calculations and inputs |
| Cadence          | Average, maximum and time series; distinguish averages including/excluding zero                                                 |
| Speed            | Average, maximum and time series; label duration basis and source                                                               |
| Elevation        | Ascent, descent, high, low and curve; explain correction and source; gradients/climbs require calculated results                |
| Training load    | Named method and activity result; historical metrics require sufficient history and supported calculations                      |
| Laps/splits      | Time, distance and available metrics; distinguish recorded laps, computed distance splits and detected intervals                |
| Cycling dynamics | Available left/right balance, pedal smoothness and torque effectiveness, with single-side availability explicit                 |

Balance uses a left-share curve and a 50% reference, with paired summary values
when supported by field semantics. Smoothness and torque effectiveness use
labeled left/right series, distinguishable line styles and an axis covering the
valid data. Raw sample views can be an optional mode on the same page. Mobile
lap rows show lap number, duration and a selected metric, with more detail on
selection; wide tables can scroll inside their own region.

## Charts, maps and data states

Use elapsed time as the default horizontal coordinate, preserving pauses and
sampling gaps. Distance is an explicit alternate axis. Linked plots and maps
share a selected time within the activity; selection displays actual samples.
Preserve valid zeros, absent samples and partial coverage distinctly. Display
simplification preserves endpoints, gaps and important extrema and affects only
rendering. Authoritative statistics come from the backend and use the same
result version as the displayed series.

Desktop charts support hover, click to pin, and Escape to release. Mobile detail
charts support sample selection while preserving vertical page scrolling.
Provide keyboard/sample navigation, selected-value text and a table/list
alternative. Zoom and range selection have controls in addition to dragging.
Animation respects reduced-motion preferences.

The overview map shows a complete route, start/end and a clear route-analysis
entry while preserving page scrolling and accessible provider attribution.
Route analysis connects a large map to time/elevation controls. Repeated visits
to one location resolve against the selected time range. Canonical tracks remain
WGS84; provider-specific display adaptation belongs at the map boundary.

| State                | Presentation                                                              |
| -------------------- | ------------------------------------------------------------------------- |
| No recorded category | Omit its overview module; explain in sources when useful                  |
| Summary only         | Show the summary and explain sample availability                          |
| Ready                | Show available content                                                    |
| Pending              | Show processing status for expected results                               |
| Load failure         | Keep a local error and retry action                                       |
| Partial coverage     | Keep usable data and explain coverage limits                              |
| Reprocessing         | Keep the usable result with its version/status until replacement is ready |

No GPS means no map module. A basemap/network failure with an existing route
keeps its own retry state. Methods, time zones, units and sources are accessible
from the relevant result. Distinguish measurement, device estimation, calculated
results and AI interpretation; display precision follows the data's meaning.

## Source settings and privacy

When source-coordinate settings are implemented, label them as the input
source's coordinate interpretation: Automatic, WGS84 or GCJ-02. Show the effective
choice and its basis, with user choice ahead of verified source rules and a
clearly labeled fallback for unknown sources. Bind rules to the identified
source/device instance; present identifying details with sensitive parts masked.

A saved setting applies to future imports. Offer historical reprocessing
separately with the affected range and count, deriving again from original input.
Present results consistently after replacement and retain usable data on failure.
The UI consumes backend policy and status; this design does not introduce a
background-job architecture or redefine import semantics.

Use recorded-source wording for imported files. Route sharing/export requires an
explicit scope; any display-only privacy masking preserves source data. AI data
transfer follows the user's provider/sharing settings. Precise routes and device
identifiers require explicit handling under the [security rules](ai/security.md).
Map-provider requests also belong in the data/privacy explanation.

## Scope and implementation boundaries

The design focus is personal training review. Social features, friends, route
libraries, badges and leaderboards remain outside product scope. Today, trends
and AI are future information-architecture ideas whose pages need their own
specifications. Dark theme, replay and multi-metric comparison are separate
follow-up design work.

Implement ordinary, task-specific components as features need them: navigation,
activity summary, metric preview, analysis view, time-series chart, route map and
source/settings forms. The frontend owns presentation and interaction; backend
rules own data, calculations and authorization. Follow the existing
[Web engineering guide](ai/web.md), [API rules](ai/api.md) and
[canonical-data rules](ai/domain-data.md). Rendering mode and deployment choices
remain in executable configuration and architecture decisions.

## Acceptance for each implemented slice

Validate the same workflow on desktop and mobile in the same feature slice.
Start with the desktop baseline and companion mobile layout, then include the
relevant intermediate sizes and edge cases.

| Area                   | Evidence to collect                                                                                                                      |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Layout                 | Desktop baselines, mobile top/middle/bottom scroll positions, intermediate reflow; aligned grid and readable chart area                  |
| Text and accessibility | 200% text enlargement, contrast, focus, keyboard, screen-reader names, reduced motion; primary touch targets at least 44 × 44 CSS pixels |
| Navigation             | Direct detail navigation, refresh/back, scroll/focus restoration, bottom content reachable                                               |
| Charts                 | Zero vs missing, gaps, partial coverage, summary-only data, real sample selection and axis/unit consistency                              |
| Failures               | Missing data, processing and recoverable errors remain distinguishable                                                                   |
| Imports and sources    | Backend-backed duplicate handling, completion while away, explicit reprocessing scope and recoverable failures                           |
| Privacy                | Synthetic/minimized fixtures and deliberate provider data boundaries                                                                     |

For implemented features, report viewports, actual browsers/devices, commands,
results and skipped checks. Browser emulation and real mobile Safari testing are
reported separately. Use layout measurements and visual review together. Choose
any comparison experiment around a concrete task, such as finding mean heart
rate, selecting a sample or returning to the overview.
