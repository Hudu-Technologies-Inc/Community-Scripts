# Assets and Fields

## Highlighting Filled ListSelect Values

While we can't highlight content based on the content itself, we can highlight values based on their inherited properties. In this case, we're targeting properties that status fields or listselect fields posess.

<img width="954" height="586" alt="image" src="https://github.com/user-attachments/assets/c52259ec-e02b-4752-a7b6-c09e66a8a786" />

```css
/* rounded-style highlight background values */
.card__item-slot:nth-child(2):not(:has(*)) {
display: inline-block;
padding: 4px 10px;
border-radius: 999px;
background: rgba(222,222,15,0.25);
}
```

## Enlarging Status or Listselect Values / Labels

Similar to above, other styles can be applied based on similar or same criterion.

This can be applied to some fields (if a given property is present) or all fields
<img width="1062" height="828" alt="image" src="https://github.com/user-attachments/assets/57648ff2-701b-4374-b416-e2a99fa380fc" />

```css
.card__item-slot:first-child {
  /* Text and Font Styling */
    color: #333; /* Text color */
    font-family: Arial, sans-serif; /* Font family */
    font-size: 16px; /* Font size */
    font-weight: bold; /* Bold text */
    font-style: italic; /* Italicize text */
    text-transform: uppercase; /* Uppercase text */
    letter-spacing: 1px; /* Space between characters */
    text-decoration: underline; /* Underlined text */
    line-height: 1.5; /* Line spacing */
}
```
or more simply- 

<img width="1080" height="564" alt="image" src="https://github.com/user-attachments/assets/b2200f31-2720-4fd3-ace5-71808aae97f5" />

```css
/* Status field VALUE */
.card__item > .card__item-slot:first-child {
/* optional: style the LABEL */
}
.card__item > .card__item-slot:first-child + .card__item-slot {
/* default value styles (do nothing here) */
}
/* Only apply when value slot is plain text (Status case) */
.card__item > .card__item-slot:first-child + .card__item-slot:not(:has(*)) {
font-weight: 800;
}
```

## Highlighting Danger-Flagged Fields and Values

This can be helpful for marking critical or sensitive fields, increasing emphasis on certain facets of your assets

<img width="834" height="832" alt="image" src="https://github.com/user-attachments/assets/38f6f247-a478-4b27-93e7-6fd49cd69d7c" />

```css
/* Highlight cards that contain danger icons */
.card__item:has(.danger) {
background: rgba(244,247,54,0.12);
}
```

## Emphasizing or Styling Backgrounds for Fields or Values in Assets

Just as an example, here's what is needed to apply a background gradient to either values or fields. While not particularly pretty, it serves as a good example for any decoration or style one might choose.

Labels-
<img width="1108" height="866" alt="image" src="https://github.com/user-attachments/assets/ea6d109f-bf32-44c9-8157-06382d63b91e" />

```css
.card__item-slot:nth-child(1) { background: linear-gradient( 90deg, #000000 1%, rgba(255,255,255,0.1) 50% ); }
.card__item-slot:nth-child(1):not(:has(*)) {
box-shadow: inset 0 0 0 1px rgba(255,255,255,0.03);
}
```

Values-
<img width="1646" height="668" alt="image" src="https://github.com/user-attachments/assets/4dbfa133-8f1d-42dd-b693-0a46b907dea2" />

```css
.card__item-slot:nth-child(2) { background: linear-gradient( 90deg, #000000 1%, rgba(255,255,255,0.1) 50% ); }
.card__item-slot:nth-child(2):not(:has(*)) {
box-shadow: inset 0 0 0 1px rgba(255,255,255,0.03);
}
```
