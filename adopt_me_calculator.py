"""
Adopt Me Trade Value Calculator
A standalone Python GUI tool to calculate pet trade values.
Values sourced from community data (August 2026).
Use alongside Roblox while trading in Adopt Me.
"""

import tkinter as tk
import sys
import traceback

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

# ============ PET VALUES DATABASE (RP - Ride Potion equivalents) ============
# Values from Traderie / community data, August 2026
PET_VALUES = {
    # --- Legendary (Top Tier) ---
    "bat dragon": 940,
    "shadow dragon": 844,
    "giraffe": 475,
    "frost dragon": 326,
    "owl": 246,
    "giant panda": 211,
    "parrot": 196,
    "crow": 175,
    "balloon unicorn": 165,
    "blazing lion": 155,
    "evil unicorn": 108,
    "orchid butterfly": 103,
    "hedgehog": 65,
    "monkey king": 64,
    "diamond butterfly": 61,
    "undead jousting horse": 60,
    "jekyll hydra": 59,
    "dalmatian": 58,
    "arctic reindeer": 49,
    "strawberry tortle": 47,
    "frostbite bear": 42,
    "african wild dog": 153,
    "cryptid": 133,
    "haetae": 117,

    # --- Legendary (Mid Tier) ---
    "turtle": 32,
    "kangaroo": 30,
    "faker frost dragon": 28,
    "octopus": 14,
    "dragon": 11,
    "griffin": 10,
    "unicorn": 9,
    "kitsune": 8,
    "toucan": 6,
    "robin": 5,
    "snow owl": 5,
    "metal ox": 3,
    "golden unicorn": 3,
    "golden griffin": 3,
    "golden dragon": 3,
    "queen bee": 4,
    "diamond egg": 3,
    "roc": 4,
    "phoenix": 4,
    "skeletal Rex": 5,
    "swan": 12,

    # --- Legendary (Low Tier) ---
    "dodo": 3,
    "trex": 3,
    "sloth": 2,
    "frost fury": 6,
    "lava dragon": 4,
    "neon shadow dragon": 1688,
    "neon bat dragon": 1880,
    "neon frost dragon": 652,
    "neon giraffe": 950,

    # --- Ultra Rare ---
    "snake": 3,
    "elephant": 14,
    "cow": 12,
    "sheep": 6,
    "platypus": 5,
    "red panda": 4,
    "penguin": 3,
    "koala": 2,
    "hippo": 2,
    "bunny": 1,
    "cat": 1,
    "dog": 1,
    "chick": 1,
    "flamingo": 8,
    "chocolate labrador": 1,

    # --- Rare ---
    "pig": 4,
    "horse": 1,
    "stegosaurus": 1,
    "triceratops": 1,
    "raptor": 1,
    "wolf": 1,
    "fox": 1,
    "bear": 1,
    "donkey": 1,
    "rabbit": 1,
    "snow cat": 1,

    # --- Eggs ---
    "frost egg": 8,
    "royal egg": 4,
    "egg": 2,
    "cracked egg": 1,
    "pet egg": 1,

    # --- Vehicles ---
    "mr car": 2,
    "hoverboard": 1,

    # --- Toys ---
    "ride potion": 1,
    "fly potion": 3,
    "frost wing": 2,
}


def lookup_value(name):
    """Look up a pet value by name (case-insensitive, fuzzy match)."""
    key = name.lower().strip()
    if key in PET_VALUES:
        return PET_VALUES[key]
    # Try partial match
    for pet_name, val in PET_VALUES.items():
        if key in pet_name or pet_name in key:
            return val
    return None


class PlaceholderEntry(tk.Entry):
    """Entry with placeholder text that clears on focus and restores if empty."""

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

    def _on_focus_in(self, _event):
        if self._showing_placeholder:
            self.delete(0, "end")
            self.config(fg=TEXT)
            self._showing_placeholder = False

    def _on_focus_out(self, _event):
        if not self.get().strip():
            self._put_placeholder()

    def get_value(self):
        if self._showing_placeholder:
            return ""
        return self.get().strip()

    def set_text(self, text):
        self._showing_placeholder = False
        self.config(fg=TEXT)
        self.delete(0, "end")
        self.insert(0, text)

    def clear(self):
        self._put_placeholder()
        self.focus_set()


class PetEntry:
    def __init__(self, parent_frame, name, value, on_remove):
        self.name = name
        self.value = value

        self.frame = tk.Frame(parent_frame, bg=INPUT_BG, bd=0, highlightthickness=0)
        self.frame.pack(fill="x", padx=4, pady=2)

        self.name_lbl = tk.Label(
            self.frame, text=name, font=("Segoe UI", 10),
            bg=INPUT_BG, fg=TEXT, anchor="w", padx=6
        )
        self.name_lbl.pack(side="left", fill="x", expand=True)

        self.val_lbl = tk.Label(
            self.frame, text=str(value), font=("Segoe UI", 10, "bold"),
            bg=INPUT_BG, fg=GOLD, padx=6
        )
        self.val_lbl.pack(side="left")

        self.del_btn = tk.Label(
            self.frame, text=" X ", font=("Segoe UI", 9, "bold"),
            bg=INPUT_BG, fg=RED, cursor="hand2", padx=4
        )
        self.del_btn.pack(side="right", padx=4)
        self.del_btn.bind("<Button-1>", lambda e: on_remove(self))

    def destroy(self):
        self.frame.destroy()


class AutocompleteDropdown:
    """Dropdown that shows matching pet names as user types."""

    def __init__(self, parent_entry, on_select):
        self.entry = parent_entry
        self.on_select = on_select
        self.window = None
        self.listbox = None

    def show(self, matches):
        self.hide()
        if not matches:
            return

        # Position below the entry
        x = self.entry.winfo_rootx()
        y = self.entry.winfo_rooty() + self.entry.winfo_height()
        w = self.entry.winfo_width()

        self.window = tk.Toplevel(self.entry)
        self.window.wm_overrideredirect(True)
        self.window.wm_geometry(f"{w}x{min(len(matches), 6) * 22}+{x}+{y}")

        self.listbox = tk.Listbox(
            self.window,
            font=("Segoe UI", 10),
            bg=INPUT_BG,
            fg=TEXT,
            selectbackground=LINE,
            selectforeground=GOLD,
            highlightthickness=1,
            highlightcolor=LINE,
            borderwidth=0,
            activestyle="none",
        )
        self.listbox.pack(fill="both", expand=True)

        for match in matches:
            val = PET_VALUES.get(match, "?")
            self.listbox.insert("end", f"{match.title()}  ({val} RP)")

        self.listbox.bind("<ButtonRelease-1>", self._on_click)
        self.listbox.bind("<Return>", self._on_enter)
        self.listbox.select_set(0)

        # Close on click outside
        self.entry.bind("<FocusOut>", lambda e: self.hide())

    def hide(self):
        if self.window:
            self.window.destroy()
            self.window = None
            self.listbox = None

    def _on_click(self, _event):
        self._select()

    def _on_enter(self, _event):
        self._select()

    def _select(self):
        if not self.listbox:
            return
        sel = self.listbox.curselection()
        if not sel:
            return
        text = self.listbox.get(sel[0])
        # Extract pet name (before the value part)
        pet_name = text.split("  (")[0]
        self.entry.set_text(pet_name)
        self.hide()
        self.on_select(pet_name)


class TradeCalculator:
    def __init__(self, root):
        self.root = root
        self.root.title("Adopt Me - Trade Value Calculator")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)
        self.root.geometry("560x580")

        self.your_panel = None
        self.their_panel = None

        # --- Header ---
        hdr = tk.Frame(root, bg=PANEL, height=36)
        hdr.pack(fill="x")
        tk.Label(
            hdr, text="ADOPT ME - TRADE VALUE CALCULATOR",
            font=("Segoe UI", 11, "bold"), bg=PANEL, fg=GOLD
        ).pack(side="left", padx=12, pady=8)

        tk.Label(
            hdr, text=f"{len(PET_VALUES)} pets loaded",
            font=("Segoe UI", 8), bg=PANEL, fg=DIM
        ).pack(side="right", padx=12, pady=8)

        # --- Main content (two panels) ---
        body = tk.Frame(root, bg=BG)
        body.pack(fill="both", expand=True, padx=8, pady=(8, 0))

        self.your_frame = self._build_panel(body, "YOUR PETS", GREEN, 0)
        self.their_frame = self._build_panel(body, "TRADER'S PETS", BLUE, 1)

        # --- Result bar with value comparison ---
        res_frame = tk.Frame(root, bg=PANEL, bd=0, highlightthickness=0)
        res_frame.pack(fill="x", padx=8, pady=(4, 4))

        # Your side bar
        your_bar_frame = tk.Frame(res_frame, bg=BG, height=20)
        your_bar_frame.pack(fill="x", padx=8, pady=(6, 2))
        your_bar_frame.pack_propagate(False)

        tk.Label(
            your_bar_frame, text="YOU", font=("Segoe UI", 8, "bold"),
            bg=BG, fg=GREEN, width=4
        ).pack(side="left")

        your_bar_bg = tk.Frame(your_bar_frame, bg=LINE, height=14)
        your_bar_bg.pack(side="left", fill="x", expand=True, padx=(2, 4))
        your_bar_bg.pack_propagate(False)

        self.your_bar = tk.Frame(your_bar_bg, bg=GREEN, height=14)
        self.your_bar.place(x=0, y=0, relheight=1, relwidth=0)

        self.your_val_lbl = tk.Label(
            your_bar_frame, text="0", font=("Segoe UI", 9, "bold"),
            bg=BG, fg=GREEN, width=8
        )
        self.your_val_lbl.pack(side="right")

        # Their side bar
        their_bar_frame = tk.Frame(res_frame, bg=BG, height=20)
        their_bar_frame.pack(fill="x", padx=8, pady=2)
        their_bar_frame.pack_propagate(False)

        tk.Label(
            their_bar_frame, text="THEM", font=("Segoe UI", 8, "bold"),
            bg=BG, fg=BLUE, width=4
        ).pack(side="left")

        their_bar_bg = tk.Frame(their_bar_frame, bg=LINE, height=14)
        their_bar_bg.pack(side="left", fill="x", expand=True, padx=(2, 4))
        their_bar_bg.pack_propagate(False)

        self.their_bar = tk.Frame(their_bar_bg, bg=BLUE, height=14)
        self.their_bar.place(x=0, y=0, relheight=1, relwidth=0)

        self.their_val_lbl = tk.Label(
            their_bar_frame, text="0", font=("Segoe UI", 9, "bold"),
            bg=BG, fg=BLUE, width=8
        )
        self.their_val_lbl.pack(side="right")

        # Verdict text
        self.result_lbl = tk.Label(
            res_frame, text="Add pets to both sides to compare values",
            font=("Segoe UI", 10, "bold"), bg=PANEL, fg=DIM, pady=6
        )
        self.result_lbl.pack(fill="x")

        tk.Label(
            root,
            text="Type a pet name - value auto-fills from database  |  Press Enter to add",
            font=("Segoe UI", 8), bg=BG, fg=DIM
        ).pack(pady=(0, 6))

    def _build_panel(self, parent, title, accent, col):
        outer = tk.Frame(parent, bg=accent, bd=0, highlightthickness=0)
        outer.grid(row=0, column=col, sticky="nsew", padx=(0, 4) if col == 0 else (4, 0))
        parent.columnconfigure(col, weight=1)
        parent.rowconfigure(0, weight=1)

        inner = tk.Frame(outer, bg=PANEL)
        inner.pack(fill="both", expand=True, padx=1, pady=1)

        # Title
        tk.Label(
            inner, text=title, font=("Segoe UI", 10, "bold"),
            bg=PANEL, fg=accent, anchor="w", padx=8, pady=6
        ).pack(fill="x")

        # Input row
        inp_frame = tk.Frame(inner, bg=PANEL)
        inp_frame.pack(fill="x", padx=6, pady=(0, 4))

        name_entry = PlaceholderEntry(
            inp_frame, placeholder="Pet name",
            font=("Segoe UI", 10),
            bg=INPUT_BG, insertbackground=TEXT,
            relief="flat", highlightthickness=1, highlightcolor=LINE
        )
        name_entry.pack(side="left", fill="x", expand=True, ipady=3)

        val_entry = PlaceholderEntry(
            inp_frame, placeholder="0",
            font=("Segoe UI", 10),
            bg=INPUT_BG, insertbackground=TEXT,
            relief="flat", highlightthickness=1, highlightcolor=LINE,
            width=6, justify="center"
        )
        val_entry.pack(side="left", padx=(4, 0), ipady=3)

        add_btn = tk.Button(
            inp_frame, text="+ ADD", font=("Segoe UI", 9, "bold"),
            bg=BTN_ADD, fg="white", activebackground="#3aa060",
            relief="flat", cursor="hand2", padx=8
        )
        add_btn.pack(side="left", padx=(4, 0))

        # Autocomplete dropdown
        dropdown = AutocompleteDropdown(name_entry, lambda pet_name: self._on_pet_selected(pet_name, val_entry))

        def on_name_typed(_event):
            text = name_entry.get_value().lower().strip()
            if not text:
                dropdown.hide()
                return
            matches = [p for p in PET_VALUES if text in p][:6]
            dropdown.show(matches)

        def on_name_leave(_event):
            # Delay hide so dropdown click can register
            root.after(150, dropdown.hide)

        name_entry.bind("<KeyRelease>", on_name_typed)
        name_entry.bind("<FocusOut>", on_name_leave)

        # Scrollable pet list
        list_canvas = tk.Canvas(inner, bg=PANEL, highlightthickness=0, bd=0)
        scrollbar = tk.Scrollbar(inner, orient="vertical", command=list_canvas.yview)
        list_frame = tk.Frame(list_canvas, bg=PANEL)

        list_frame.bind("<Configure>", lambda e: list_canvas.configure(scrollregion=list_canvas.bbox("all")))
        list_canvas.create_window((0, 0), window=list_frame, anchor="nw")
        list_canvas.configure(yscrollcommand=scrollbar.set)

        list_canvas.pack(side="left", fill="both", expand=True, padx=(6, 0))
        scrollbar.pack(side="right", fill="y", padx=(0, 6))

        # Total label
        total_var = tk.StringVar(value="TOTAL: 0")
        total_lbl = tk.Label(
            inner, textvariable=total_var, font=("Segoe UI", 11, "bold"),
            bg=PANEL, fg=accent, anchor="e", padx=8, pady=6
        )
        total_lbl.pack(fill="x")

        # State
        pets = []

        def get_total():
            return sum(p.value for p in pets)

        def refresh_total():
            total_var.set(f"TOTAL: {get_total()}")
            self._update_result()

        def add_pet(_event=None):
            name = name_entry.get_value()
            raw_val = val_entry.get_value()
            try:
                value = int(raw_val)
            except (ValueError, TypeError):
                return
            if not name or value <= 0:
                return

            def on_remove(entry):
                if entry in pets:
                    pets.remove(entry)
                entry.destroy()
                refresh_total()

            entry = PetEntry(list_frame, name, value, on_remove)
            pets.append(entry)
            name_entry.clear()
            val_entry.clear()
            refresh_total()

        add_btn.config(command=add_pet)
        val_entry.bind("<Return>", add_pet)
        name_entry.bind("<Return>", lambda e: val_entry.focus_set())

        # Store refs for external access
        panel_ref = type("Panel", (), {
            "get_total": get_total,
            "pets": pets,
        })()

        if col == 0:
            self.your_panel = panel_ref
        else:
            self.their_panel = panel_ref

        return outer

    def _on_pet_selected(self, pet_name, val_entry):
        """Auto-fill value when a pet is selected from dropdown."""
        val = lookup_value(pet_name)
        if val is not None:
            val_entry.set_text(str(val))

    def _update_result(self):
        if not self.your_panel or not self.their_panel:
            return
        yours = self.your_panel.get_total()
        theirs = self.their_panel.get_total()
        diff = yours - theirs

        # Update value labels
        self.your_val_lbl.config(text=str(yours))
        self.their_val_lbl.config(text=str(theirs))

        # Update bars (scale to whichever side is larger, minimum 1 to avoid div/0)
        max_val = max(yours, theirs, 1)
        self.your_bar.place(x=0, y=0, relheight=1, relwidth=yours / max_val)
        self.their_bar.place(x=0, y=0, relheight=1, relwidth=theirs / max_val)

        if yours == 0 and theirs == 0:
            self.result_lbl.config(text="Add pets to both sides to compare values", fg=DIM)
            return

        if abs(diff) <= 1:
            verdict = "FAIR TRADE"
            color = GREEN
        elif diff > 0:
            ratio = yours / theirs if theirs > 0 else 0
            verdict = f"YOU OVERPAY BY {diff}  (you give {ratio:.1f}x more)"
            color = RED
        else:
            ratio = yours / theirs if theirs > 0 else 0
            verdict = f"YOU UNDERPAY BY {abs(diff)}  (you give {ratio:.1f}x less)"
            color = GREEN

        self.result_lbl.config(
            text=f"YOU: {yours}  |  THEM: {theirs}  |  {verdict}",
            fg=color
        )


if __name__ == "__main__":
    try:
        root = tk.Tk()
        app = TradeCalculator(root)
        root.mainloop()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
