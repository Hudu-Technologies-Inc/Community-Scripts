# Search And Navigation Customization Options

## Adjusting Search Bar Order in Main Navbar
To explicitly place your search bar on the far-left or far-right of your top navigation bar, here's a good starting point.

#### left-aligned search
<img width="1002" height="43" alt="image" src="https://github.com/user-attachments/assets/f9b4433f-09b5-4332-bdb1-c7072aa7fc28" />

```CSS
.header__search { order: -1; }
```
#### right-aligned search

<img width="1007" height="47" alt="image" src="https://github.com/user-attachments/assets/c6a5b067-c974-4745-a01c-b3455170624b" />
```CSS
.header__search { order: 999; }
```

## Generally-Customizing Fonts, Style, Justification, and More
Below are a few examples that can be a great starting point or reference for Hudu users that want to granularly customize Hudu's core navbar or search box
<img width="996" height="46" alt="image" src="https://github.com/user-attachments/assets/5f2d191c-7b69-4096-91bd-86474ed36aa7" />

```CSS
.header__search {
    max-width: 360px;
    margin-left: auto;
    margin-right: auto;
    text-align: left;
    border-radius: 4px;
    font-size: 0.95rem;
    background: white;
    border: 1px var(--whites2) solid;
    padding: 0 0.65rem;
    justify-content: flex-start;
    width: 100%;
    transition: all 0.6s;
}

.header__search {
    max-width: 360px;
    margin-left: auto;
    margin-right: 1rem;
    text-align: left;
    border-radius: 4px;
    font-size: 0.95rem;
    background: white;
    border: 1px var(--whites2) solid;
    padding: 0 0.65rem;
    justify-content: flex-start;
    width: 100%;
    transition: all 0.6s;
}
```
