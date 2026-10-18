---
name: Fleet Trust Engine
colors:
  surface: '#faf8ff'
  surface-dim: '#d2d9f4'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#eaedff'
  surface-container-high: '#e2e7ff'
  surface-container-highest: '#dae2fd'
  on-surface: '#131b2e'
  on-surface-variant: '#434655'
  inverse-surface: '#283044'
  inverse-on-surface: '#eef0ff'
  outline: '#737686'
  outline-variant: '#c3c6d7'
  surface-tint: '#0053db'
  primary: '#004ac6'
  on-primary: '#ffffff'
  primary-container: '#2563eb'
  on-primary-container: '#eeefff'
  inverse-primary: '#b4c5ff'
  secondary: '#006c49'
  on-secondary: '#ffffff'
  secondary-container: '#6cf8bb'
  on-secondary-container: '#00714d'
  tertiary: '#784b00'
  on-tertiary: '#ffffff'
  tertiary-container: '#996100'
  on-tertiary-container: '#ffeedd'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#dbe1ff'
  primary-fixed-dim: '#b4c5ff'
  on-primary-fixed: '#00174b'
  on-primary-fixed-variant: '#003ea8'
  secondary-fixed: '#6ffbbe'
  secondary-fixed-dim: '#4edea3'
  on-secondary-fixed: '#002113'
  on-secondary-fixed-variant: '#005236'
  tertiary-fixed: '#ffddb8'
  tertiary-fixed-dim: '#ffb95f'
  on-tertiary-fixed: '#2a1700'
  on-tertiary-fixed-variant: '#653e00'
  background: '#faf8ff'
  on-background: '#131b2e'
  surface-variant: '#dae2fd'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.025em
  display-lg-mobile:
    fontFamily: Inter
    fontSize: 26px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 22px
    letterSpacing: -0.005em
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: '0'
  body-sm:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: '0'
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.025em
  mono-metric:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.03em
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-desktop: 1.5rem
  margin: 1rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1rem
  space-xl: 1.5rem
  space-2xl: 2rem
---

## Brand & Style

This design system drives an enterprise fleet risk engine and driver compliance platform. It balances institutional authority with high-speed operational agility. Target users—risk officers, logistics dispatchers, fleet directors, and compliance screeners—operate in high-stakes environments where decisions must be executed accurately without visual fatigue.

The aesthetic is precision-driven Corporate Modern with high-density data presentation:
- **Tone:** Methodical, unassailable, crisp, and performant.
- **Visual Weight:** Light-dominant, using pure white cards on cool slate surfaces to segment data streams cleanly.
- **Hierarchy:** High information density organized through strict grid boundaries, subtle 1px dividers, tabular alignments, and micro-metric counters.
- **Affordance:** Clear segregation between interactive actions (vibrant cobalt blue) and trust/verification state indicators (pure emerald green).

## Colors

The palette emphasizes immediate status verification, distinct interactive signals, and clear data hierarchy:

- **Surface & Canvas:**
  - Background Canvas: `#f8fafc` (Slate 50)
  - Card & Container Surface: `#ffffff` (Pure White)
  - Subtle Muted Surface: `#f1f5f9` (Slate 100)
  - Borders & Outlines: `#e2e8f0` (Slate 200)
  - Interactive/Hover Borders: `#cbd5e1` (Slate 300)

- **Typography & Neutrals:**
  - Primary Typography: `#0f172a` (Slate 900)
  - Secondary / Supporting: `#475569` (Slate 600)
  - Muted / Placeholder: `#94a3b8` (Slate 400)

- **Interactive Primary (`#2563eb` - Vibrant Cobalt):**
  - Reserved strictly for forward user actions, selected states, tab active bars, interactive links, and primary execution triggers.
  - Primary Hover: `#1d4ed8`
  - Subtle Tint (Interactive Selected): `#eff6ff`

- **Trust & Verification Secondary (`#10b981` - Emerald Green):**
  - Reserved exclusively for verified states, high safety scores, passed MVR/background checks, and healthy operational telemetry.
  - Emerald Surface Wash: `#ecfdf5`
  - Emerald Border Accent: `#a7f3d0`

- **Warning & Critical Alerts:**
  - Warning/Attention (Tertiary): `#f59e0b` (Amber 500) | Surface: `#fffbeb`
  - Critical/Disqualified: `#ef4444` (Red 500) | Surface: `#fef2f2`

## Typography

Typography relies on `Inter` across all structural layers to enforce legibility in data-dense tables, analytical widgets, and onboarding audit logs:

- Enable tabular lining figures (`font-feature-settings: "tnum" 1`) across all metric displays, tabular rows, telemetry counters, and timestamp cells to prevent horizontal layout shift.
- Strict visual hierarchy ensures metadata remains subordinate to actual risk values and operational names.
- All uppercase label variants (`label-sm`) require tracking (`letter-spacing: 0.025em` to `0.05em`) for legibility in badge indicators and table column headers.

## Layout & Spacing

The layout is built for high information density, rapid scanning, and side-by-side verification:

- **Grid Strategy:** A fluid 12-column grid system anchored by an outer margin of `2rem` (32px) on desktop and `1rem` (16px) on mobile viewports. Gutters sit at `1.5rem` (24px) for desktop data grids, shrinking to `1rem` (16px) for tablet and sub-dashboard panels.
- **Density Scaling:** A baseline 4px/8px incremental scale (`space-xs` = 4px, `space-sm` = 8px, `space-md` = 12px, `space-lg` = 16px, `space-xl` = 24px) guarantees predictable vertical cadence. Compact tables and toolbars leverage `space-xs` and `space-sm` for padded items to maximize above-the-fold screen space.
- **Breakpoints:**
  - `Mobile` (< 768px): Single-column reflow; secondary metric streams convert into scrollable horizontal segments or stacked cards.
  - `Tablet / Laptop` (768px - 1279px): Collapsible left navigation rail (64px icon-only), 2-column scorecard setups.
  - `Desktop` (1280px+): Persistent 256px fleet directory/navigation bar, flexible 12-column analytical canvas, and optional 380px drawer for real-time driver credential inspection.

## Elevation & Depth

This system avoids heavy shadows, instead relying on tonal layering, sharp micro-borders, and subtle ambient deflections to emphasize clarity:

- **Border Hierarchy:** Primary containment occurs via `1px solid #e2e8f0` (Slate 200). Surface elevation sits against `#f8fafc` with crisp `#ffffff` cards.
- **Level 0 (Flat Container):** `#ffffff` background with `1px solid #e2e8f0` and no shadow. Used for default scorecard grids, standard table cells, and static data boxes.
- **Level 1 (Resting Cards & Metrics):** `0 1px 2px 0 rgba(15, 23, 42, 0.04), 0 1px 3px 0 rgba(15, 23, 42, 0.02)` coupled with a `1px solid #e2e8f0` boundary.
- **Level 2 (Active/Hover/Flyout):** Used for interactive row states, active card lift, and simple tooltips: `0 4px 6px -1px rgba(15, 23, 42, 0.06), 0 2px 4px -2px rgba(15, 23, 42, 0.04)`.
- **Level 3 (Modals, Slide-over Drawers, Floating Command Bars):** `0 20px 25px -5px rgba(15, 23, 42, 0.08), 0 8px 10px -6px rgba(15, 23, 42, 0.04)` over a `rgba(15, 23, 42, 0.4)` backdrop blur overlay (`backdrop-filter: blur(4px)`).

## Shapes

The geometric framework balances technical precision with modern enterprise ergonomics:

- **Core Radius (`roundedness: 1`):** Base components (input controls, standard cards, contextual menus, data tables) use a `0.25rem` to `0.375rem` (4px-6px) edge radius, delivering an intentional, crisp instrument feel.
- **Pill Exceptions:** High-density status badges, metric indicator tags, and navigation segment switchers (pill tabs) employ full-radius rounded capsules (`9999px`) to immediately set them apart from structural card boundaries.
- **Interactive States:** Retain consistent edge geometry upon focus; inputs and buttons never morph outer shapes, ensuring rock-solid spatial stability across dynamic updates.

## Components

- **Buttons:**
  - *Primary:* Filled `#2563eb`, white label, 36px height (`px-3.5 py-1.5`), `text-body-sm` font weight 600, rounded 6px. Hover: `#1d4ed8`. Focus: `2px ring` of `#93c5fd` with 1px white offset.
  - *Secondary / Outline:* Crisp `#ffffff` fill, `1px solid #e2e8f0`, label `#0f172a`. Hover: `#f8fafc`, border `#cbd5e1`.
  - *Verified Action:* Filled `#10b981`, white label, used for critical single-step trust validations and driver pass certifications.

- **Status Badges & Chips:**
  - Full pill radius (`rounded-full`), height 22px, `px-2.5 py-0.5`, `label-sm` with tabular positioning.
  - *Verified / Low Risk:* Background `#ecfdf5`, text `#065f46`, border `1px solid #a7f3d0`. Includes a 6px solid `#10b981` status dot.
  - *Pending / Audit:* Background `#eff6ff`, text `#1e40af`, border `1px solid #bfdbfe`.
  - *Flagged / High Risk:* Background `#fef2f2`, text `#991b1b`, border `1px solid #fecaca`.

- **Pill Tabs & Navigation Switches:**
  - Contained segment track in `#f1f5f9` with 6px internal padding.
  - Tab items use full pill shape or 6px matching radius; inactive tab is transparent with `#475569` text.
  - Active tab is `#ffffff` with a crisp `1px solid rgba(0,0,0,0.06)` container shadow and bold `#0f172a` text.

- **Metrics Counters & KPI Tiles:**
  - Card baseline: `#ffffff`, 1px border `#e2e8f0`, `p-4` padding.
  - Top line: `label-sm` uppercase `#475569` with optional status badge aligned top-right.
  - Center: `mono-metric` `#0f172a` with tabular numeral sizing.
  - Bottom indicator: Micro delta tracker (e.g., `+4.2% safety index`) in `#10b981` with directional micro-arrow.

- **Data Tables & Driver Onboarding Lists:**
  - Header row: `#f8fafc`, border-bottom `1px solid #e2e8f0`, uppercase `label-sm` `#475569`, 36px row height.
  - Content rows: `#ffffff`, alternate hover state `#f8fafc`, 48px standard row height, border-bottom `1px solid #f1f5f9`.
  - Selection: Row selection highlights the row with `#eff6ff` wash and a 2px left border accent in `#2563eb`.

- **Inputs & Form Controls:**
  - Height 36px, border `1px solid #cbd5e1`, background `#ffffff`, text `body-md` `#0f172a`, placeholder `#94a3b8`.
  - Focus state: Border `#2563eb`, outline ring `3px rgba(37, 99, 235, 0.15)`.
  - Error state: Border `#ef4444`, outline ring `3px rgba(239, 68, 68, 0.15)`.

- **Cards & Inspection Panels:**
  - Divided by clean horizontal section breaks (`border-t 1px solid #f1f5f9`).
  - Card header features integrated action button groups and high-contrast credential titles.