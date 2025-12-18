# Magic Dashes

**Mental model**

Magic Dash cards do not expose semantic data (field names, values) directly to CSS.
Instead, styling is done by matching **structure, state, icons, and metadata**.
Most “logic” is achieved using structural selectors and `:has()` rather than text matching.

## Example - Emphasizing / Basic Styling

<img width="1676" height="1058" alt="image" src="https://github.com/user-attachments/assets/9786c51a-9bae-4d8d-9a2b-8ed8357cd240" />

from example:
```css
/* Overall Magic Dash card sizing */
.custom-fast-fact {
padding: 18px 20px !important;
border-radius: 16px;
margin-bottom: 14px;
}
/* Header row */
.custom-fast-fact__header {
display: flex;
align-items: center;
gap: 10px;
margin-bottom: 10px;
}
/* Header icon */
.custom-fast-fact__header i {
font-size: 1.4rem;
opacity: 0.9;
}
/* Header title */
.custom-fast-fact__header h1 {
font-size: 1.35rem !important;
font-weight: 800;
margin: 0;
line-height: 1.2;
}
/* Magic Dash content */
.custom-fast-fact__content {
font-size: 1.08rem;
line-height: 1.55;
}
.custom-fast-fact__content p {
margin: 0;
}
/* Subtle card styling */
.custom-fast-fact {
background: rgba(255,255,15,0.44);
border: 1px solid rgba(255,255,255,0.15);
}
/* Emphasize non-null items */
.custom-fast-fact:not(.custom-fast-fact--null) {
background: rgba(90,140,255,0.32);
border-color: rgba(90,140,255,0.5);
}
```

## Modifying Style of MagicDash Cards
There are a number of properties that can be selected for when styling with CSS. In fact, MagicDashes are ideal for styling.


## Usual Properties

### Content-based selectors (via `:has()`)

Target cards based on **icons or content**, which act as semantic signals.

core card:
`.custom-fast-fact { }`

Info icon:
`.custom-fast-fact:has(.fa-info-circle) { }`

Warning / alert icon:
`.custom-fast-fact:has(.fa-exclamation-triangle) { }`

Cards with empty content:
`.custom-fast-fact:has(.custom-fast-fact__content:empty) { }`

Cards with populated content:
`.custom-fast-fact:has(.custom-fast-fact__content p) { }`

with info-circle icon / icon logic-
`.custom-fast-fact:has(.fa-info-circle) { }`

Cards with content-
`.custom-fast-fact:has(.custom-fast-fact__content p) { }`

Odd/Even:
`.custom-fast-fact:nth-child(odd) { }`
`.custom-fast-fact:nth-child(even) { }`

Header/Content:

`.custom-fast-fact__header { }`

`.custom-fast-fact__content { }`

## De-emphasize empty cards
```css
.custom-fast-fact--null {
  opacity: 0.5;
  filter: grayscale(1);
}
```


