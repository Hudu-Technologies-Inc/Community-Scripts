# Customizing Articles and Article Contents

## Enlarging Images on Hover

This can be handy for quickly expanding images for a brief detailed-view in articles and is very simple.

```CSS
.hemingway__split-content img:hover {
 width: 1000px;
 border: 5px solid rgba(0, 0, 0, .5);
}
```

## Emphasizing/Styling Article Contents

In this example, you can see that the article contents has been placed into a somewhat-subtle card, which can help make the information therein 'pop'
<img width="1768" height="554" alt="image" src="https://github.com/user-attachments/assets/fa94cd50-43b4-421d-af2c-b13cd2dcd937" />
```CSS
/* Make the rich text "stand out" like a card */
.rich_text_content {
  padding: 14px 16px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,5,0.70);
  background: rgba(255,255,5,0.07);
}
```
---

## Emphasizing/Styling Article Titles
You can change the font family, boldness, or size/style of article titles. This can make reading easier or help out when you have lots of Hudu tabs open in browser at once.
<img width="1384" height="378" alt="image" src="https://github.com/user-attachments/assets/cf3c9eae-f8a9-4e2f-81d8-3aacbbba336f" />

```CSS
#app .rich-text,
#app .article__content,
#app .asset__content {
padding: 12px 14px;
border-radius: 12px;
border: 1px solid rgba(255,255,255,0.10);
background: rgba(255,255,255,0.03);
}
```
---

## Creating a Standard Styling for Tables in Articles

If you want to style all your article tables at once, it's easier than it sounds. Whether for branding or visibiltiy, it's rather easy-

<img width="1432" height="734" alt="image" src="https://github.com/user-attachments/assets/e3e053b2-b67a-4835-8100-3fdf38043ecf" />

```css
/* Tables inside rich text */
.rich_text_content table {
width: 100%;
border-collapse: collapse;
border: 2px solid rgba(255,255,255,0.6);   /* outer border */
margin: 12px 0;
}
/* Cell borders */
.rich_text_content th,
.rich_text_content td {
padding: 10px 12px;
border: 1.5px solid rgba(255,255,255,0.45);
vertical-align: top;
}
.rich_text_content th {
background: rgba(222, 222, 15, 0.45);
color: #ffffff;
font-weight: 700;
text-align: left;
}
```

---

## Creating a Reusable Class for Collapsable Tables in Articles
<img width="1592" height="496" alt="image" src="https://github.com/user-attachments/assets/10f98931-33e9-4ce2-8b08-683e474592cf" />

For this one, we create a CSS class that can be reused between articles, which allows for collapse-on-click tables
Below, you'll find an example for this class definition

```CSS
/* Collapsible wrapper */
.rich_text_content details.hudu-collapse {
  margin: 12px 0;
  padding: 10px 12px;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.18);
  background: rgba(255,255,255,0.03);
}

/* Summary row */
.rich_text_content details.hudu-collapse > summary {
  cursor: pointer;
  font-weight: 800;
  user-select: none;
}

/* Space between summary and table when opened */
.rich_text_content details.hudu-collapse[open] > summary {
  margin-bottom: 10px;
}

/* Make the table look the same as your “noticeable” style */
.rich_text_content details.hudu-collapse table {
  width: 100%;
  border-collapse: collapse;
  border: 2px solid rgba(255,255,255,0.6);
  margin-top: 10px;
}

.rich_text_content details.hudu-collapse th,
.rich_text_content details.hudu-collapse td {
  padding: 10px 12px;
  border: 1.5px solid rgba(255,255,255,0.45);
  vertical-align: top;
}

.rich_text_content details.hudu-collapse th {
  background: rgba(90, 140, 255, 0.35);
  color: #fff;
  font-weight: 700;
  text-align: left;
}
```

And to designate this class to a table in an Article, you can simply go to 'source code view' in your article editor and put your table under our new hudu-collapse class. It will then inherit this property and style.

```HTML
<details class="hudu-collapse">
  <summary>Show table: Patch Schedule</summary>
  <table>
    <thead>
      <tr><th>Server</th><th>Window</th><th>Owner</th></tr>
    </thead>
    <tbody>
      <tr><td>app-01</td><td>Sun 2am</td><td>Ops</td></tr>
    </tbody>
  </table>
</details>
```

This example is better-used for finalized documents that aren't often edited, because it may make editing a little tricky, but could be handy for articles with many tables.
---


