---
name: Stilora
colors:
  # ── Light theme (source of truth — matches all mockups) ──
  surface: '#f9f9ff'
  surface-dim: '#d3daef'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f1f3ff'
  surface-container: '#e9edff'
  surface-container-high: '#e1e8fd'
  surface-container-highest: '#dce2f7'
  on-surface: '#141b2b'
  on-surface-variant: '#464555'
  inverse-surface: '#293040'
  inverse-on-surface: '#edf0ff'
  outline: '#777587'
  outline-variant: '#c7c4d8'
  surface-tint: '#4d44e3'
  primary: '#3525cd'
  on-primary: '#ffffff'
  primary-container: '#4f46e5'
  on-primary-container: '#dad7ff'
  inverse-primary: '#c3c0ff'
  secondary: '#0051d5'
  on-secondary: '#ffffff'
  secondary-container: '#316bf3'
  on-secondary-container: '#fefcff'
  tertiary: '#7e3000'
  on-tertiary: '#ffffff'
  tertiary-container: '#a44100'
  on-tertiary-container: '#ffd2be'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c3c0ff'
  on-primary-fixed: '#0f0069'
  on-primary-fixed-variant: '#3323cc'
  secondary-fixed: '#dbe1ff'
  secondary-fixed-dim: '#b4c5ff'
  on-secondary-fixed: '#00174b'
  on-secondary-fixed-variant: '#003ea8'
  tertiary-fixed: '#ffdbcc'
  tertiary-fixed-dim: '#ffb695'
  on-tertiary-fixed: '#351000'
  on-tertiary-fixed-variant: '#7b2f00'
  background: '#f9f9ff'
  on-background: '#141b2b'
  surface-variant: '#dce2f7'
dark:
  # ── Dark theme (same hue architecture, inverted tonal ladder) ──
  surface: '#0f1119'
  surface-dim: '#0a0c12'
  surface-bright: '#1a1d29'
  surface-container-lowest: '#0c0e15'
  surface-container-low: '#12141d'
  surface-container: '#181b26'
  surface-container-high: '#1e2130'
  surface-container-highest: '#252839'
  on-surface: '#e3e6f2'
  on-surface-variant: '#b4b6c9'
  inverse-surface: '#edf0ff'
  inverse-on-surface: '#293040'
  outline: '#8d8fa4'
  outline-variant: '#3a3d4f'
  primary: '#c3c0ff'
  on-primary: '#12005e'
  primary-container: '#4f46e5'
  on-primary-container: '#dad7ff'
  inverse-primary: '#3525cd'
  secondary: '#9dbcff'
  on-secondary: '#00174b'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  background: '#0f1119'
  on-background: '#e3e6f2'
  surface-variant: '#252839'
typography:
  # Single family: Geist (all roles, no secondary face)
  display-lg:
    fontFamily: Geist
    fontSize: 3.5rem
    fontWeight: '400'
    lineHeight: '1.1'
    letterSpacing: -0.03em
  headline-xl:
    fontFamily: Geist
    fontSize: 2.5rem
    fontWeight: '500'
    lineHeight: '1.15'
    letterSpacing: -0.025em
  headline-xl-mobile:
    fontFamily: Geist
    fontSize: 2rem
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Geist
    fontSize: 1.75rem
    fontWeight: '500'
    lineHeight: '1.25'
    letterSpacing: -0.02em
  headline-sm:
    fontFamily: Geist
    fontSize: 1.25rem
    fontWeight: '600'
    lineHeight: '1.3'
    letterSpacing: -0.015em
  body-lg:
    fontFamily: Geist
    fontSize: 1.125rem
    fontWeight: '400'
    lineHeight: '1.6'
    letterSpacing: -0.01em
  body-md:
    fontFamily: Geist
    fontSize: 0.9375rem
    fontWeight: '400'
    lineHeight: '1.55'
    letterSpacing: -0.005em
  body-sm:
    fontFamily: Geist
    fontSize: 0.8125rem
    fontWeight: '400'
    lineHeight: '1.45'
    letterSpacing: 0em
  label-md:
    fontFamily: Geist
    fontSize: 0.875rem
    fontWeight: '500'
    lineHeight: '1.2'
    letterSpacing: 0em
  label-sm:
    fontFamily: Geist
    fontSize: 0.6875rem
    fontWeight: '600'
    lineHeight: '1.1'
    letterSpacing: 0.04em
rounded:
  # Matches mockups (Tailwind map: DEFAULT 0.25rem, lg 0.5rem, xl 0.75rem)
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.5rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  gutter: 1.25rem
  gutter-mobile: 0.75rem
  margin: 2.5rem
  margin-mobile: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.5rem
motion:
  duration-instant: 100ms
  duration-fast: 150ms
  duration-normal: 200ms
  duration-slow: 300ms
  easing-standard: cubic-bezier(0.2, 0, 0, 1)
  easing-emphasized: cubic-bezier(0.3, 0, 0, 1)
focus:
  # Focus-visible ring — required on every interactive element
  ring-width: 2px
  ring-color: '#4f46e5'
  ring-offset: 2px
elevation:
  # Shadows are exceptional: only transient floating layers get one
  halo-dropdown: 0 20px 40px -15px rgba(17, 24, 39, 0.04)
  halo-dialog: 0 30px 60px -20px rgba(0, 0, 0, 0.08)
  resting: none
presence:
  online: '#0051d5'
  idle: '#ffb695'
  offline: '#c7c4d8'
  speaking: '#3525cd'
breakpoints:
  mobile: 767px
  tablet: 1024px
  desktop: 1025px
---

## Brand

**Stilora.** One name everywhere: window titles, app bars, footers, docs, store
listings. Workspace names (e.g. "Studio Flow") are *sample data*, never brand.
Logo mark: the `grain` glyph on a primary chip — identical on every screen.
Legal/security copy uses **"Encrypted in transit & at rest"** — we never claim
end-to-end encryption.

## Brand & Style

Stilora is an ultra-reductive, Scandinavian-inspired communication workspace
engineered for uninterrupted cognitive flow. Attention is a finite, precious
resource. The visual voice is quiet, measured, deliberate — no notification
clutter, no decorative embellishment, no skeuomorphic excess; breathable
structure and surgical typographical clarity instead. The emotional target is
sanctuary: calm, orderly, frictionless, deeply competent.

Audience: focused knowledge workers, systems designers, high-output teams who
need high signal-to-noise ratios.

## Colors

The palette is purple-tinted throughout — every neutral carries a faint indigo
cast so surfaces feel like one continuous atmosphere rather than gray boxes.

- Base surfaces: whisper-light `#f9f9ff` → `#dce2f7` tonal ladder; foreground
  content floats without harsh white glare.
- Text: deep indigo-black `#141b2b` (primary), `#464555` (secondary).
- **Color is syntax, never decoration.** Electric indigo `#3525cd` and cobalt
  `#4f46e5` mark active state, focus, and purposeful interaction — nothing else.
- Boundaries and secondary labels use muted `#777587` / `#c7c4d8` featherlight.
- The dark theme inverts the same tonal ladder (`#0f1119` base) with `#c3c0ff`
  as the on-dark primary. Both themes are mandatory on every screen.
- Presence dots: online `#0051d5`, idle `#ffb695`, offline `#c7c4d8`,
  speaking `#3525cd`.

## Typography

**Geist only.** Geometric, precision-machined rhythm bridging developer tools
and high-craft editorial. Tight negative tracking on display sizes binds
headings into visual units; body text keeps relaxed tracking and generous line
height for long threads. Micro-labels and status chips are uppercase with
positive tracking for glance-level comprehension.

## Layout & Spacing

Flexible fluid columns inside generous perimeter margins. Density is relaxed on
purpose; negative space is structure, not filler.

Desktop: conversations, docks and sidebars in a 12-column grid, `1.25rem`
gutters; sidebars collapse to whisper panels. Breakpoints:

- **Mobile (< 768px):** single-pane full-bleed, `1rem` margins, stacked flows.
- **Tablet (768–1024px):** 2-pane with sliding drawers, `1.5rem` margins.
- **Desktop (> 1024px):** up to 3 panes (nav · thread · context/members),
  `2.5rem` outer margins.

Spacing tokens: `0.25 / 0.5 / 1 / 1.5 / 2.5rem`.

## Elevation & Depth

No drop shadows at rest. Depth = tonal layering + whisper borders.

1. **Surface tiers:** canvas `#f9f9ff` · elevated (cards/panels/modals)
   `#ffffff` · recessed (inputs/code) `#f1f3ff`.
2. **Whisper outlines:** `1px` borders, `#c7c4d8` or `rgba(20,27,43,0.06)`.
3. **Ambient halo:** only dropdowns, command palette and dialogs get a shadow —
   the two values in the YAML frontmatter. Never a sharp shadow anywhere.
4. **Focus ring** replaces shadows as interactive feedback: 2px `#4f46e5`,
   2px offset, on every focusable element (keyboard nav requirement).

## Shapes

Structural cards/panels use `rounded-xl` (**0.75rem / 12px** — corrected from
the old 24px spec to match shipped mockups). Inputs, buttons, chips: 0.5rem.
Pills (`full`) for avatars, presence dots, badges and the voice capsule.

## Components

### Buttons
- **Primary:** solid `#4f46e5`, white label, no border, opacity 0.92 on hover.
- **Secondary/Ghost:** transparent, 1px `#e5e7eb`-equivalent border, text
  `#141b2b`; recessed `#f1f3ff` on hover.
- **Icon actions:** borderless, monochrome `#777587`, accent on focus/press only.

### Cards & thread containers
White surface, `1px rgba(20,27,43,0.06)` border, `1.5rem` padding, flat at
rest; border darkens to `#c7c4d8` on hover — never translate vertically.

### Inputs & search
Recessed `#f1f3ff` at rest, transparent border. Focus: white surface + crisp
1px `#4f46e5` ring. Placeholder `#777587` with inline monoline icons.
Command palette (⌘K): centered `#ffffff` modal with `halo-dialog`, keycaps as
`#e9edff` chips.

### Badges & notifications
No red dots. Unread = single 6px cobalt dot beside the title. Metadata chips:
`#f1f3ff` fill, `label-sm` type. Security badge copy: "Encrypted in transit &
at rest".

### Lists & activity feeds
Divided by space and hairline `#f3f4f6`-weight rules; hover washes the row
`#f9f9ff` instantly, no easing on row hovers.

### Voice capsule
Pill floating above the thread: live dot, room name, participant chips (pill
sized to content — never fixed 20px circles), count, mic + hangup controls.
Never overlaps avatars or header content; on narrow widths it wraps below.

## Screen inventory

Existing (mockups shipped): desktop sign-in · desktop workspace · desktop
settings · mobile sign-in · mobile workspace · mobile chat stream · mobile
voice/video stage.

Required by v1 (built in Flutter):

- Onboarding / account creation (email + password + workspace name)
- Thread view ("18 replies" / pins destination)
- Direct-message conversation
- Search results (⌘K)
- Channel creation modal
- Member list + user profile
- Notifications / activity feed
- Desktop voice/video stage
- Settings nav shell (profile, notifications, workspace, members, security)

## State matrix (every screen ships all of these)

| State | Rule |
|---|---|
| Loading | Skeleton blocks in surface tones — no spinners on content that has a shape |
| Empty | One calm line of copy + a single primary action |
| Error | Inline, retry action, never a full-red page |
| Offline | Persistent slim banner; cached content stays readable |
| Permission denied | Explain *why* we need mic/camera + button to system settings |
| Call connecting / reconnecting | Capsule shows status dot + label; controls stay usable |
| Send failed | Row keeps a subtle error tint + retry affordance |
| Dark mode | Full parity with light — every token above has a dark value |

## Accessibility (mandatory)

- Focus-visible ring on all interactive elements (token: `focus`).
- Touch targets ≥ 44×44px on mobile; ≥ 32px icon buttons get 44px hit areas.
- Body text ≥ 4.5:1 contrast in both themes; large text ≥ 3:1.
- Every icon-only control has a semantic label.
- Honor `prefers-reduced-motion`: cross-fades only, no ping/pulse loops.
- Respect system text scaling up to 200% without clipping.
