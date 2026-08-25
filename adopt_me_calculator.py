"""
Adopt Me Trade Value Calculator
A standalone Python GUI tool with pet images and grid trade layout.
Values sourced from community data (August 2026).
Use alongside Roblox while trading in Adopt Me.
"""

import tkinter as tk
from tkinter import messagebox
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
INPUT_BG = "#0e0e14"
BTN_ADD  = "#328c5a"

CARD_SIZE = 64

# ============ PET DATABASE ============
# (name, value, rarity_color, wiki_page)
# Values from Traderie / community, August 2026
# Wiki page names are used to fetch thumbnails from adoptme.fandom.com
PETS = [
    ("Bat Dragon",              940, GOLD,   "Bat_Dragon"),
    ("Shadow Dragon",           844, GOLD,   "Shadow_Dragon"),
    ("Giraffe",                 475, GOLD,   "Giraffe"),
    ("Frost Dragon",            326, GOLD,   "Frost_Dragon"),
    ("Owl",                     246, GOLD,   "Owl"),
    ("Giant Panda",             211, GOLD,   "Giant_Panda"),
    ("Parrot",                  196, GOLD,   "Parrot"),
    ("Crow",                    175, GOLD,   "Crow"),
    ("Balloon Unicorn",         165, GOLD,   "Balloon_Unicorn"),
    ("Blazing Lion",            155, GOLD,   "Blazing_Lion"),
    ("African Wild Dog",        153, GOLD,   "African_Wild_Dog"),
    ("Cryptid",                 133, GOLD,   "Cryptid"),
    ("Haetae",                  117, GOLD,   "Haetae"),
    ("Evil Unicorn",            108, GOLD,   "Evil_Unicorn"),
    ("Orchid Butterfly",        103, GOLD,   "Orchid_Butterfly"),
    ("Hedgehog",                 65, GOLD,   "Hedgehog"),
    ("Monkey King",              64, GOLD,   "Monkey_King"),
    ("Diamond Butterfly",        61, GOLD,   "Diamond_Butterfly"),
    ("Undead Jousting Horse",    60, GOLD,   "Undead_Jousting_Horse"),
    ("Jekyll Hydra",             59, GOLD,   "Jekyll_Hydra"),
    ("Dalmatian",                58, GOLD,   "Dalmatian"),
    ("Arctic Reindeer",          49, GOLD,   "Arctic_Reindeer"),
    ("Strawberry Tortle",        47, GOLD,   "Strawberry_Tortle"),
    ("Swan",                     12, GOLD,   "Swan"),
    ("Frost Fury",                6, GOLD,   "Frost_Fury"),
    ("Turtle",                   32, GOLD,   "Turtle"),
    ("Kangaroo",                 30, GOLD,   "Kangaroo"),
    ("Octopus",                  14, GOLD,   "Octopus"),
    ("Dragon",                   11, GOLD,   "Dragon"),
    ("Griffin",                  10, GOLD,   "Griffin"),
    ("Unicorn",                   9, GOLD,   "Unicorn"),
    ("Kitsune",                   8, GOLD,   "Kitsune"),
    ("Queen Bee",                 4, GOLD,   "Queen_Bee"),
    ("Dodo",                      3, GOLD,   "Dodo"),
    ("T-Rex",                     3, GOLD,   "T-Rex"),
    ("Sloth",                     2, GOLD,   "Sloth"),
    ("Metal Ox",                  3, GOLD,   "Metal_Ox"),
    ("Cow",                      12, "#8b8bff", "Cow"),
    ("Elephant",                 14, "#8b8bff", "Elephant"),
    ("Flamingo",                  8, "#8b8bff", "Flamingo"),
    ("Pig",                       4, "#8b8bff", "Pig"),
    ("Sheep",                     6, "#8b8bff", "Sheep"),
    ("Red Panda",                 4, "#8b8bff", "Red_Panda"),
    ("Snake",                     3, "#8b8bff", "Snake"),
    ("Penguin",                   3, "#8b8bff", "Penguin"),
    ("Koala",                     2, "#8b8bff", "Koala"),
]

PET_DB = {}
for _name, _val, _color, _wiki in PETS:
    PET_DB[_name.lower()] = {"name": _name, "value": _val, "color": _color, "wiki": _wiki}

# ============ IMAGE CACHE ============
IMG_CACHE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".pet_images")
_img_cache = {}  # wiki_page -> PhotoImage


def _fetch_image(wiki_page, size=CARD_SIZE):
    """Download a pet thumbnail from the Adopt Me wiki and return a PhotoImage."""
    if wiki_page in _img_cache:
        return _img_cache[wiki_page]

    url = (
        f"https://adoptme.fandom.com/api.php?action=query&titles={wiki_page}"
        f"&prop=pageimages&format=json&pithumbsize={size * 2}"
    )
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "AdoptMeCalc/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = resp.read()
        import json
        pages = json.loads(data).get("query", {}).get("pages", {})
        for page in pages.values():
            thumb = page.get("thumbnail", {}).get("source")
            if thumb:
                req2 = urllib.request.Request(thumb, headers={"User-Agent": "AdoptMeCalc/1.0"})
                with urllib.request.urlopen(req2, timeout=8) as resp2:
                    img_data = resp2.read()
                img = Image.open(io.BytesIO(img_data)).convert("RGBA")
                img = img.resize((size, size), Image.LANCZOS)
                photo = ImageTk.PhotoImage(img)
                _img_cache[wiki_page] = photo
                return photo
    except Exception:
        pass

    # Fallback: return None (caller draws a placeholder)
    return None


def get_pet_image(wiki_page, size=CARD_SIZE):
    """Get or cache a pet image, returning PhotoImage or None."""
    return _fetch_image(wiki_page, size)


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
            highlightthickness=1, highlightcolor=LINE,
            borderwidth=0, activestyle="none",
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
    """A single pet card with image, name, and value."""

    def __init__(self, parent, pet_info, on_remove):
        self.pet_info = pet_info
        super().__init__(parent, bg=PANEL, width=CARD_SIZE + 16, height=CARD_SIZE + 36)
        self.pack_propagate(False)

        # Image
        self.img_label = tk.Label(self, bg=PANEL, width=CARD_SIZE, height=CARD_SIZE)
        self.img_label.pack(pady=(4, 2))

        wiki = pet_info.get("wiki", "")
        photo = get_pet_image(wiki) if wiki else None
        if photo:
            self.img_label.config(image=photo)
            self._photo = photo  # prevent GC
        else:
            # Placeholder: colored circle with initial
            self.img_label.config(
                text=pet_info["name"][0].upper(),
                font=("Segoe UI", 18, "bold"),
                fg=GOLD,
            )

        # Name
        tk.Label(
            self, text=pet_info["name"], font=("Segoe UI", 8),
            bg=PANEL, fg=TEXT, wraplength=CARD_SIZE + 10
        ).pack()

        # Value
        tk.Label(
            self, text=f"{pet_info['value']} RP", font=("Segoe UI", 8, "bold"),
            bg=PANEL, fg=GOLD
        ).pack()

        # Delete button (small X in corner)
        del_btn = tk.Label(
            self, text="X", font=("Segoe UI", 7, "bold"),
            bg=PANEL, fg=RED, cursor="hand2"
        )
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

        self.your_cards = []
        self.their_cards = []

        # --- Header ---
        hdr = tk.Frame(root, bg=PANEL, height=40)
        hdr.pack(fill="x")
        tk.Label(
            hdr, text="ADOPT ME - TRADE VALUE CALCULATOR",
            font=("Segoe UI", 12, "bold"), bg=PANEL, fg=GOLD
        ).pack(side="left", padx=12, pady=8)
        tk.Label(
            hdr, text=f"{len(PETS)} pets loaded",
            font=("Segoe UI", 8), bg=PANEL, fg=DIM
        ).pack(side="right", padx=12)

        # --- Main trade area (two sides) ---
        trade_area = tk.Frame(root, bg=BG)
        trade_area.pack(fill="both", expand=True, padx=8, pady=(8, 0))

        self.your_frame = self._build_side(trade_area, "YOUR OFFER", GREEN, 0)
        self.their_frame = self._build_side(trade_area, "THEIR OFFER", BLUE, 1)

        # --- Bottom result area ---
        bottom = tk.Frame(root, bg=PANEL)
        bottom.pack(fill="x", padx=8, pady=8)

        # Value bars
        bar_area = tk.Frame(bottom, bg=PANEL)
        bar_area.pack(fill="x", padx=8, pady=(4, 2))

        # Your bar
        your_row = tk.Frame(bar_area, bg=PANEL)
        your_row.pack(fill="x", pady=1)
        tk.Label(your_row, text="YOU", font=("Segoe UI", 8, "bold"),
                 bg=PANEL, fg=GREEN, width=5).pack(side="left")
        your_bar_bg = tk.Frame(your_row, bg=LINE, height=12)
        your_bar_bg.pack(side="left", fill="x", expand=True, padx=(0, 6))
        your_bar_bg.pack_propagate(False)
        self.your_bar = tk.Frame(your_bar_bg, bg=GREEN, height=12)
        self.your_bar.place(x=0, y=0, relheight=1, relwidth=0)
        self.your_val = tk.Label(your_row, text="0", font=("Segoe UI", 9, "bold"),
                                 bg=PANEL, fg=GREEN, width=7)
        self.your_val.pack(side="right")

        # Their bar
        their_row = tk.Frame(bar_area, bg=PANEL)
        their_row.pack(fill="x", pady=1)
        tk.Label(their_row, text="THEM", font=("Segoe UI", 8, "bold"),
                 bg=PANEL, fg=BLUE, width=5).pack(side="left")
        their_bar_bg = tk.Frame(their_row, bg=LINE, height=12)
        their_bar_bg.pack(side="left", fill="x", expand=True, padx=(0, 6))
        their_bar_bg.pack_propagate(False)
        self.their_bar = tk.Frame(their_bar_bg, bg=BLUE, height=12)
        self.their_bar.place(x=0, y=0, relheight=1, relwidth=0)
        self.their_val = tk.Label(their_row, text="0", font=("Segoe UI", 9, "bold"),
                                  bg=PANEL, fg=BLUE, width=7)
        self.their_val.pack(side="right")

        # Verdict
        self.verdict = tk.Label(
            bottom, text="Add pets to both sides to compare values",
            font=("Segoe UI", 11, "bold"), bg=PANEL, fg=DIM, pady=6
        )
        self.verdict.pack(fill="x")

    def _build_side(self, parent, title, accent, col):
        outer = tk.Frame(parent, bg=accent, bd=0)
        outer.grid(row=0, column=col, sticky="nsew", padx=(0, 4) if col == 0 else (4, 0))
        parent.columnconfigure(col, weight=1)
        parent.rowconfigure(0, weight=1)

        inner = tk.Frame(outer, bg=PANEL)
        inner.pack(fill="both", expand=True, padx=1, pady=1)

        # Title bar
        title_frame = tk.Frame(inner, bg=PANEL)
        title_frame.pack(fill="x", padx=8, pady=(6, 4))
        tk.Label(title_frame, text=title, font=("Segoe UI", 10, "bold"),
                 bg=PANEL, fg=accent).pack(side="left")
        total_var = tk.StringVar(value="0 RP")
        total_lbl = tk.Label(title_frame, textvariable=total_var,
                             font=("Segoe UI", 10, "bold"), bg=PANEL, fg=accent)
        total_lbl.pack(side="right")

        # Input row
        inp = tk.Frame(inner, bg=PANEL)
        inp.pack(fill="x", padx=6, pady=(0, 4))

        name_entry = PlaceholderEntry(inp, placeholder="Pet name",
                                      font=("Segoe UI", 9), bg=INPUT_BG,
                                      fg=TEXT, insertbackground=TEXT,
                                      relief="flat", highlightthickness=1,
                                      highlightcolor=LINE)
        name_entry.pack(side="left", fill="x", expand=True, ipady=2)

        val_entry = PlaceholderEntry(inp, placeholder="RP",
                                     font=("Segoe UI", 9), bg=INPUT_BG,
                                     fg=TEXT, insertbackground=TEXT,
                                     relief="flat", highlightthickness=1,
                                     highlightcolor=LINE, width=5, justify="center")
        val_entry.pack(side="left", padx=(3, 0), ipady=2)

        add_btn = tk.Button(inp, text="+", font=("Segoe UI", 10, "bold"),
                            bg=BTN_ADD, fg="white", activebackground="#3aa060",
                            relief="flat", cursor="hand2", width=3)
        add_btn.pack(side="left", padx=(3, 0))

        # Card grid (scrollable)
        grid_canvas = tk.Canvas(inner, bg=PANEL, highlightthickness=0, bd=0)
        grid_scroll = tk.Scrollbar(inner, orient="vertical", command=grid_canvas.yview)
        grid_frame = tk.Frame(grid_canvas, bg=PANEL)

        grid_frame.bind("<Configure>", lambda e: grid_canvas.configure(scrollregion=grid_canvas.bbox("all")))
        grid_canvas.create_window((0, 0), window=grid_frame, anchor="nw")
        grid_canvas.configure(yscrollcommand=grid_scroll.set)

        grid_canvas.pack(side="left", fill="both", expand=True, padx=(6, 0))
        grid_scroll.pack(side="right", fill="y", padx=(0, 4))

        # State
        cards = []

        def get_total():
            return sum(c.pet_info["value"] for c in cards)

        def refresh():
            total_var.set(f"{get_total()} RP")
            self._update_result()

        def add_pet(_event=None):
            name = name_entry.get_value()
            raw_val = val_entry.get_value()

            # Try database lookup first
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
                pet = {"name": name, "value": value, "color": TEXT, "wiki": ""}

            def on_remove(card):
                if card in cards:
                    cards.remove(card)
                card.destroy()
                # Recalculate row layout
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

        # Autocomplete
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

        # Store ref
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
