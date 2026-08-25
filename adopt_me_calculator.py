"""
Adopt Me Trade Value Calculator
A standalone Python GUI tool with pet images and grid trade layout.
Values sourced from community data (August 2026).
Use alongside Roblox while trading in Adopt Me.
"""

import tkinter as tk
import sys
import os
import io
import urllib.request
import traceback
from PIL import Image, ImageTk

# ============ THEME ============
BG       = "#121218"
PANEL    = "#1c1c26"
LINE     = "#37374b"
TEXT     = "#e6e6f0"
DIM      = "#8c8ca5"
GREEN    = "#3ca06e"
BLUE     = "#6e82dc"
GOLD     = "#c8aa50"
RED      = "#c84b4b"
PURPLE   = "#a87ddb"
PINK     = "#d47db8"
INPUT_BG = "#0e0e14"
BTN_ADD  = "#328c5a"

CARD_SIZE = 64

# ============ PET DATABASE ============
# name, value (RP), color, image_url
# Values from Traderie / community data, August 2026
# Images from adoptme.fandom.com (individual pet thumbnails)
_IMG = "https://static.wikia.nocookie.net/adoptme/images"

PETS = [
    # --- Legendary (S+ Tier, 100+ RP) ---
    ("Bat Dragon",              940, GOLD,   f"{_IMG}/8/8c/Bat_Dragon.png/revision/latest/scale-to-width-down/100?cb=20191229182905"),
    ("Shadow Dragon",           844, GOLD,   f"{_IMG}/f/f7/ShadowDragon_Pet.png/revision/latest/scale-to-width-down/100?cb=20200116014549"),
    ("Giraffe",                 475, GOLD,   f"{_IMG}/6/6c/Giraffe_Pet.png/revision/latest/scale-to-width-down/100?cb=20200204215159"),
    ("Frost Dragon",            326, GOLD,   f"{_IMG}/6/6c/FrostDragon.jpg/revision/latest/scale-to-width-down/100?cb=20210323151008"),
    ("Owl",                     246, GOLD,   f"{_IMG}/6/69/Owl_AM.jpg/revision/latest/scale-to-width-down/100?cb=20200922143717"),
    ("Giant Panda",             211, GOLD,   f"{_IMG}/c/cc/Giant_Panda.png/revision/latest/scale-to-width-down/100?cb=20250911161443"),
    ("Parrot",                  196, GOLD,   f"{_IMG}/8/83/Parrotonjungleegg.jpg/revision/latest/scale-to-width-down/100?cb=20210503014228"),
    ("Crow",                    175, GOLD,   f"{_IMG}/e/eb/Legendary_Crow_pet.png/revision/latest/scale-to-width-down/100?cb=20240907224746"),
    ("Balloon Unicorn",         165, GOLD,   f"{_IMG}/1/1a/Balloon_Unicorn_inventory.png/revision/latest/scale-to-width-down/100?cb=20240628191240"),
    ("Blazing Lion",            155, GOLD,   f"{_IMG}/3/32/Blazing_Lion.png/revision/latest/scale-to-width-down/100?cb=20260721050538"),
    ("African Wild Dog",        153, GOLD,   f"{_IMG}/3/3f/African_Wild_Dog.png/revision/latest/scale-to-width-down/100?cb=20230710163102"),
    ("Cryptid",                 133, GOLD,   f"{_IMG}/5/52/Cryptid.png/revision/latest/scale-to-width-down/100?cb=20251015153956"),
    ("Haetae",                  117, GOLD,   f"{_IMG}/a/a3/Haetae.png/revision/latest/scale-to-width-down/100?cb=20250129224752"),
    ("Evil Unicorn",            108, GOLD,   f"{_IMG}/8/81/EvilUnicorn_Pet.png/revision/latest/scale-to-width-down/100?cb=20200723085043"),
    ("Orchid Butterfly",        103, GOLD,   f"{_IMG}/5/5b/Orchid_Butterfly.png/revision/latest/scale-to-width-down/100?cb=20250602163245"),

    # --- Legendary (A Tier, 10-100 RP) ---
    ("Hedgehog",                 65, GOLD,   f"{_IMG}/3/3d/Hedgehog_After.png/revision/latest/scale-to-width-down/100?cb=20200411171415"),
    ("Monkey King",              64, GOLD,   None),
    ("Diamond Butterfly",        61, GOLD,   f"{_IMG}/a/a4/Diamond_Butterfly_in-game..png/revision/latest/scale-to-width-down/100?cb=20220805025520"),
    ("Undead Jousting Horse",    60, GOLD,   f"{_IMG}/d/d9/The_teaser_image_of_the_Undead_Jousting_Horse.png/revision/latest/scale-to-width-down/100?cb=20221024180049"),
    ("Jekyll Hydra",             59, GOLD,   f"{_IMG}/0/04/Jekyll_Hydra.png/revision/latest/scale-to-width-down/100?cb=20241021225246"),
    ("Dalmatian",                58, GOLD,   f"{_IMG}/0/01/The_Dalmatian.png/revision/latest/scale-to-width-down/100?cb=20210311011919"),
    ("Arctic Reindeer",          49, GOLD,   f"{_IMG}/1/1d/The_Arctic_Reindeer_Display.png/revision/latest/scale-to-width-down/100?cb=20191231033232"),
    ("Strawberry Tortle",        47, GOLD,   f"{_IMG}/a/aa/Strawberry_Tortle.png/revision/latest/scale-to-width-down/100?cb=20260821151946"),
    ("Frostbite Bear",           42, GOLD,   None),
    ("Turtle",                   32, GOLD,   f"{_IMG}/3/3f/Turtle_In-game..png/revision/latest/scale-to-width-down/100?cb=20210617223738"),
    ("Kangaroo",                 30, GOLD,   f"{_IMG}/7/7b/The_Kangaroo_in_inventory.png/revision/latest/scale-to-width-down/100?cb=20231206204012"),
    ("Albino Monkey",            30, GOLD,   None),
    ("Golden Penguin",           15, GOLD,   None),
    ("Octopus",                  14, GOLD,   f"{_IMG}/4/4a/Octopus_In_Game.png/revision/latest/scale-to-width-down/100?cb=20210418142857"),
    ("Swan",                     12, GOLD,   f"{_IMG}/0/05/Swalet.png/revision/latest/scale-to-width-down/100?cb=20201112141914"),
    ("Cow",                      12, GOLD,   None),
    ("Elephant",                 14, GOLD,   None),
    ("Dragon",                   11, GOLD,   f"{_IMG}/7/71/Dragon_In_Game.jpg/revision/latest/scale-to-width-down/100?cb=20200426135211"),
    ("Griffin",                  10, GOLD,   f"{_IMG}/d/de/Griffin_%28display%29.PNG/revision/latest/scale-to-width-down/100?cb=20210706202534"),
    ("Unicorn",                   9, GOLD,   f"{_IMG}/c/c8/Unicorn_in-game.png/revision/latest/scale-to-width-down/100?cb=20260119060025"),
    ("Flamingo",                  8, GOLD,   None),
    ("Kitsune",                   8, GOLD,   f"{_IMG}/4/4a/A_Kitsune_in-game.png/revision/latest/scale-to-width-down/100?cb=20221201053159"),
    ("Frost Fury",                6, GOLD,   None),
    ("Sheep",                     6, GOLD,   None),
    ("Queen Bee",                 4, GOLD,   f"{_IMG}/a/ab/A_Normal_Queen_Bee.png/revision/latest/scale-to-width-down/100?cb=20210306020051"),
    ("Pig",                       4, GOLD,   None),
    ("Red Panda",                 4, GOLD,   None),
    ("Dodo",                      3, GOLD,   f"{_IMG}/2/2c/The_Dodo_on_display.jpg/revision/latest/scale-to-width-down/100?cb=20210430030718"),
    ("T-Rex",                     3, GOLD,   f"{_IMG}/9/9d/T-rex.png/revision/latest/scale-to-width-down/100?cb=20210726155718"),
    ("Metal Ox",                  3, GOLD,   f"{_IMG}/f/f9/Metal_Ox_AM.png/revision/latest/scale-to-width-down/100?cb=20210202200524"),
    ("Snake",                     3, GOLD,   None),
    ("Penguin",                   3, GOLD,   None),
    ("Sloth",                     2, GOLD,   f"{_IMG}/0/05/Slothy.png/revision/latest/scale-to-width-down/100?cb=20201113122102"),
    ("Koala",                     2, GOLD,   None),
    ("Golden Unicorn",            3, GOLD,   None),
    ("Golden Griffin",            3, GOLD,   None),
    ("Golden Dragon",             3, GOLD,   None),
    ("Neon Frost Fury",          18, GOLD,   None),

    # --- Ultra-Rare ---
    ("Robot",                     3, PURPLE, None),
    ("Starfish",                  3, PURPLE, None),
    ("Silly Duck",                3, PURPLE, None),
    ("Snow Leopard",              2, PURPLE, None),
    ("Polar Bear",                2, PURPLE, None),
    ("Reindeer",                  2, PURPLE, None),
    ("Spider",                    2, PURPLE, None),
    ("Husky",                     2, PURPLE, None),
    ("Beaver",                    1, PURPLE, None),
    ("Rabbit",                    1, PURPLE, None),
    ("Puma",                      1, PURPLE, None),
    ("Fox",                       1, PURPLE, None),

    # --- Rare ---
    ("Wolf",                      1, BLUE,   None),
    ("Stegosaurus",               1, BLUE,   None),
    ("Triceratops",               1, BLUE,   None),
    ("Raptor",                    1, BLUE,   None),
    ("Horse",                     1, BLUE,   None),
    ("Cat",                       1, BLUE,   None),
    ("Dog",                       1, BLUE,   None),
    ("Snow Cat",                  1, BLUE,   None),
    ("Donkey",                    1, BLUE,   None),
    ("Bear",                      1, BLUE,   None),

    # --- Uncommon ---
    ("Fennec Fox",                1, GREEN,  None),
    ("Snow Puma",                 1, GREEN,  None),
    ("Monkey",                    1, GREEN,  None),
    ("Chick",                     1, GREEN,  None),
    ("Blue Dog",                  1, GREEN,  None),
    ("Pink Cat",                  1, GREEN,  None),
    ("Buffalo",                   1, GREEN,  None),
    ("Otter",                     1, GREEN,  None),

    # --- Common ---
    ("Chicken",                   1, DIM,    None),

    # --- Items ---
    ("Ride Potion",               1, TEXT,    None),
    ("Fly Potion",                3, TEXT,    None),
]

# Build lookup dict (lowercase name -> info)
PET_DB = {}
for _name, _val, _color, _url in PETS:
    PET_DB[_name.lower()] = {"name": _name, "value": _val, "color": _color, "img_url": _url}

# ============ IMAGE CACHE ============
_img_cache = {}  # url -> PhotoImage


def get_pet_image(url, size=CARD_SIZE):
    """Download a pet image from URL and return PhotoImage, or None."""
    if not url:
        return None
    if url in _img_cache:
        return _img_cache[url]
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AdoptMeCalc/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = resp.read()
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        img = img.resize((size, size), Image.LANCZOS)
        photo = ImageTk.PhotoImage(img)
        _img_cache[url] = photo
        return photo
    except Exception:
        return None


def lookup_pet(name):
    key = name.lower().strip()
    if key in PET_DB:
        return PET_DB[key]
    for k, v in PET_DB.items():
        if key in k or k in key:
            return v
    return None


# ============ PLACEHOLDER ENTRY ============
class PlaceholderEntry(tk.Entry):
    def __init__(self, master, placeholder="", **kwargs):
        self.placeholder = placeholder
        self._showing_placeholder = True
        kwargs.setdefault("fg", DIM)
        super().__init__(master, **kwargs)
        self._put_placeholder()
        self.bind("<FocusIn>", self._on_focus_in)
        self.bind("<FocusOut>", self._on_focus_out)

    def _put_placeholder(self):
        self._showing_placeholder = True
        self.config(fg=DIM)
        self.delete(0, "end")
        self.insert(0, self.placeholder)

    def _on_focus_in(self, _e):
        if self._showing_placeholder:
            self.delete(0, "end")
            self.config(fg=TEXT)
            self._showing_placeholder = False

    def _on_focus_out(self, _e):
        if not self.get().strip():
            self._put_placeholder()

    def get_value(self):
        return "" if self._showing_placeholder else self.get().strip()

    def set_text(self, text):
        self._showing_placeholder = False
        self.config(fg=TEXT)
        self.delete(0, "end")
        self.insert(0, text)

    def clear(self):
        self._put_placeholder()
        self.focus_set()


# ============ AUTOCOMPLETE ============
class AutocompleteDropdown:
    def __init__(self, parent_entry, on_select):
        self.entry = parent_entry
        self.on_select = on_select
        self.window = None
        self.listbox = None

    def show(self, matches):
        self.hide()
        if not matches:
            return
        x = self.entry.winfo_rootx()
        y = self.entry.winfo_rooty() + self.entry.winfo_height()
        w = self.entry.winfo_width()
        self.window = tk.Toplevel(self.entry)
        self.window.wm_overrideredirect(True)
        self.window.wm_geometry(f"{w}x{min(len(matches), 6) * 24}+{x}+{y}")
        self.listbox = tk.Listbox(
            self.window, font=("Segoe UI", 10), bg=INPUT_BG, fg=TEXT,
            selectbackground=LINE, selectforeground=GOLD,
            highlightthickness=1, highlightcolor=LINE, borderwidth=0, activestyle="none",
        )
        self.listbox.pack(fill="both", expand=True)
        for m in matches:
            info = PET_DB.get(m, {})
            val = info.get("value", "?")
            self.listbox.insert("end", f"{info.get('name', m.title())}  ({val} RP)")
        self.listbox.bind("<ButtonRelease-1>", lambda e: self._select())
        self.listbox.bind("<Return>", lambda e: self._select())
        self.listbox.select_set(0)
        self.entry.bind("<FocusOut>", lambda e: self.hide())

    def hide(self):
        if self.window:
            self.window.destroy()
            self.window = None
            self.listbox = None

    def _select(self):
        if not self.listbox:
            return
        sel = self.listbox.curselection()
        if not sel:
            return
        text = self.listbox.get(sel[0]).split("  (")[0]
        self.entry.set_text(text)
        self.hide()
        self.on_select(text)


# ============ PET CARD ============
class PetCard(tk.Frame):
    def __init__(self, parent, pet_info, on_remove):
        self.pet_info = pet_info
        super().__init__(parent, bg=PANEL, width=CARD_SIZE + 16, height=CARD_SIZE + 36)
        self.pack_propagate(False)

        self.img_label = tk.Label(self, bg=PANEL, width=CARD_SIZE, height=CARD_SIZE)
        self.img_label.pack(pady=(4, 2))

        url = pet_info.get("img_url")
        photo = get_pet_image(url) if url else None
        if photo:
            self.img_label.config(image=photo)
            self._photo = photo
        else:
            self.img_label.config(
                text=pet_info["name"][0].upper(),
                font=("Segoe UI", 18, "bold"),
                fg=pet_info.get("color", GOLD),
            )

        tk.Label(self, text=pet_info["name"], font=("Segoe UI", 8),
                 bg=PANEL, fg=TEXT, wraplength=CARD_SIZE + 10).pack()
        tk.Label(self, text=f"{pet_info['value']} RP", font=("Segoe UI", 8, "bold"),
                 bg=PANEL, fg=GOLD).pack()

        del_btn = tk.Label(self, text="X", font=("Segoe UI", 7, "bold"),
                           bg=PANEL, fg=RED, cursor="hand2")
        del_btn.place(x=CARD_SIZE + 2, y=0)
        del_btn.bind("<Button-1>", lambda e: on_remove(self))


# ============ MAIN CALCULATOR ============
class TradeCalculator:
    def __init__(self, root):
        self.root = root
        self.root.title("Adopt Me - Trade Value Calculator")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)
        self.root.geometry("660x620")

        # --- Header ---
        hdr = tk.Frame(root, bg=PANEL, height=40)
        hdr.pack(fill="x")
        tk.Label(hdr, text="ADOPT ME - TRADE VALUE CALCULATOR",
                 font=("Segoe UI", 12, "bold"), bg=PANEL, fg=GOLD).pack(side="left", padx=12, pady=8)
        tk.Label(hdr, text=f"{len(PETS)} pets loaded", font=("Segoe UI", 8),
                 bg=PANEL, fg=DIM).pack(side="right", padx=12)

        # --- Trade area ---
        trade_area = tk.Frame(root, bg=BG)
        trade_area.pack(fill="both", expand=True, padx=8, pady=(8, 0))
        self.your_frame = self._build_side(trade_area, "YOUR OFFER", GREEN, 0)
        self.their_frame = self._build_side(trade_area, "THEIR OFFER", BLUE, 1)

        # --- Bottom result ---
        bottom = tk.Frame(root, bg=PANEL)
        bottom.pack(fill="x", padx=8, pady=8)

        bar_area = tk.Frame(bottom, bg=PANEL)
        bar_area.pack(fill="x", padx=8, pady=(4, 2))

        # Your bar
        your_row = tk.Frame(bar_area, bg=PANEL)
        your_row.pack(fill="x", pady=1)
        tk.Label(your_row, text="YOU", font=("Segoe UI", 8, "bold"),
                 bg=PANEL, fg=GREEN, width=5).pack(side="left")
        ybb = tk.Frame(your_row, bg=LINE, height=12)
        ybb.pack(side="left", fill="x", expand=True, padx=(0, 6))
        ybb.pack_propagate(False)
        self.your_bar = tk.Frame(ybb, bg=GREEN, height=12)
        self.your_bar.place(x=0, y=0, relheight=1, relwidth=0)
        self.your_val = tk.Label(your_row, text="0", font=("Segoe UI", 9, "bold"),
                                 bg=PANEL, fg=GREEN, width=7)
        self.your_val.pack(side="right")

        # Their bar
        their_row = tk.Frame(bar_area, bg=PANEL)
        their_row.pack(fill="x", pady=1)
        tk.Label(their_row, text="THEM", font=("Segoe UI", 8, "bold"),
                 bg=PANEL, fg=BLUE, width=5).pack(side="left")
        tbb = tk.Frame(their_row, bg=LINE, height=12)
        tbb.pack(side="left", fill="x", expand=True, padx=(0, 6))
        tbb.pack_propagate(False)
        self.their_bar = tk.Frame(tbb, bg=BLUE, height=12)
        self.their_bar.place(x=0, y=0, relheight=1, relwidth=0)
        self.their_val = tk.Label(their_row, text="0", font=("Segoe UI", 9, "bold"),
                                  bg=PANEL, fg=BLUE, width=7)
        self.their_val.pack(side="right")

        self.verdict = tk.Label(bottom, text="Add pets to both sides to compare values",
                                font=("Segoe UI", 11, "bold"), bg=PANEL, fg=DIM, pady=6)
        self.verdict.pack(fill="x")

    def _build_side(self, parent, title, accent, col):
        outer = tk.Frame(parent, bg=accent)
        outer.grid(row=0, column=col, sticky="nsew", padx=(0, 4) if col == 0 else (4, 0))
        parent.columnconfigure(col, weight=1)
        parent.rowconfigure(0, weight=1)

        inner = tk.Frame(outer, bg=PANEL)
        inner.pack(fill="both", expand=True, padx=1, pady=1)

        title_frame = tk.Frame(inner, bg=PANEL)
        title_frame.pack(fill="x", padx=8, pady=(6, 4))
        tk.Label(title_frame, text=title, font=("Segoe UI", 10, "bold"),
                 bg=PANEL, fg=accent).pack(side="left")
        total_var = tk.StringVar(value="0 RP")
        tk.Label(title_frame, textvariable=total_var, font=("Segoe UI", 10, "bold"),
                 bg=PANEL, fg=accent).pack(side="right")

        inp = tk.Frame(inner, bg=PANEL)
        inp.pack(fill="x", padx=6, pady=(0, 4))

        name_entry = PlaceholderEntry(inp, placeholder="Pet name", font=("Segoe UI", 9),
                                      bg=INPUT_BG, fg=TEXT, insertbackground=TEXT,
                                      relief="flat", highlightthickness=1, highlightcolor=LINE)
        name_entry.pack(side="left", fill="x", expand=True, ipady=2)

        val_entry = PlaceholderEntry(inp, placeholder="RP", font=("Segoe UI", 9),
                                     bg=INPUT_BG, fg=TEXT, insertbackground=TEXT,
                                     relief="flat", highlightthickness=1, highlightcolor=LINE,
                                     width=5, justify="center")
        val_entry.pack(side="left", padx=(3, 0), ipady=2)

        add_btn = tk.Button(inp, text="+", font=("Segoe UI", 10, "bold"),
                            bg=BTN_ADD, fg="white", activebackground="#3aa060",
                            relief="flat", cursor="hand2", width=3)
        add_btn.pack(side="left", padx=(3, 0))

        grid_canvas = tk.Canvas(inner, bg=PANEL, highlightthickness=0, bd=0)
        grid_scroll = tk.Scrollbar(inner, orient="vertical", command=grid_canvas.yview)
        grid_frame = tk.Frame(grid_canvas, bg=PANEL)
        grid_frame.bind("<Configure>", lambda e: grid_canvas.configure(scrollregion=grid_canvas.bbox("all")))
        grid_canvas.create_window((0, 0), window=grid_frame, anchor="nw")
        grid_canvas.configure(yscrollcommand=grid_scroll.set)
        grid_canvas.pack(side="left", fill="both", expand=True, padx=(6, 0))
        grid_scroll.pack(side="right", fill="y", padx=(0, 4))

        cards = []

        def get_total():
            return sum(c.pet_info["value"] for c in cards)

        def refresh():
            total_var.set(f"{get_total()} RP")
            self._update_result()

        def add_pet(_event=None):
            name = name_entry.get_value()
            raw_val = val_entry.get_value()
            pet = lookup_pet(name) if name else None
            if pet:
                value = pet["value"]
            else:
                try:
                    value = int(raw_val)
                except (ValueError, TypeError):
                    return
                if not name or value <= 0:
                    return
                pet = {"name": name, "value": value, "color": TEXT, "img_url": None}

            def on_remove(card):
                if card in cards:
                    cards.remove(card)
                card.destroy()
                for i, c in enumerate(cards):
                    c.grid(row=i // 4, column=i % 4, padx=4, pady=4)
                refresh()

            card = PetCard(grid_frame, pet, on_remove)
            card.grid(row=len(cards) // 4, column=len(cards) % 4, padx=4, pady=4)
            cards.append(card)
            name_entry.clear()
            val_entry.clear()
            refresh()

        add_btn.config(command=add_pet)
        val_entry.bind("<Return>", add_pet)
        name_entry.bind("<Return>", lambda e: val_entry.focus_set())

        dropdown = AutocompleteDropdown(name_entry, lambda pn: self._on_select(pn, val_entry))

        def on_type(_e):
            t = name_entry.get_value().lower().strip()
            if not t:
                dropdown.hide()
                return
            matches = [k for k in PET_DB if t in k][:6]
            dropdown.show(matches)

        name_entry.bind("<KeyRelease>", on_type)
        name_entry.bind("<FocusOut>", lambda e: self.root.after(150, dropdown.hide))

        ref = type("Side", (), {})()
        ref.get_total = get_total
        ref.cards = cards
        if col == 0:
            self.your_side = ref
        else:
            self.their_side = ref
        return outer

    def _on_select(self, pet_name, val_entry):
        pet = lookup_pet(pet_name)
        if pet:
            val_entry.set_text(str(pet["value"]))

    def _update_result(self):
        yours = self.your_side.get_total()
        theirs = self.their_side.get_total()
        diff = yours - theirs
        self.your_val.config(text=str(yours))
        self.their_val.config(text=str(theirs))
        mx = max(yours, theirs, 1)
        self.your_bar.place(x=0, y=0, relheight=1, relwidth=yours / mx)
        self.their_bar.place(x=0, y=0, relheight=1, relwidth=theirs / mx)

        if yours == 0 and theirs == 0:
            self.verdict.config(text="Add pets to both sides to compare values", fg=DIM)
            return
        if abs(diff) <= 1:
            text, color = "FAIR TRADE", GREEN
        elif diff > 0:
            r = yours / theirs if theirs > 0 else 0
            text, color = f"YOU OVERPAY BY {diff} ({r:.1f}x)", RED
        else:
            r = yours / theirs if theirs > 0 else 0
            text, color = f"YOU UNDERPAY BY {abs(diff)} ({r:.1f}x)", GREEN
        self.verdict.config(text=f"YOU: {yours}  |  THEM: {theirs}  |  {text}", fg=color)


if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = TradeCalculator(root)
        root.mainloop()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
