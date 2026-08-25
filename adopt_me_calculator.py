"""
Adopt Me Trade Value Calculator
A standalone Python GUI tool to calculate pet trade values.
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


class TradeCalculator:
    def __init__(self, root):
        self.root = root
        self.root.title("Adopt Me - Trade Value Calculator")
        self.root.configure(bg=BG)
        self.root.resizable(False, False)
        self.root.geometry("560x520")

        self.your_panel = None
        self.their_panel = None

        # --- Header ---
        hdr = tk.Frame(root, bg=PANEL, height=36)
        hdr.pack(fill="x")
        tk.Label(
            hdr, text="ADOPT ME - TRADE VALUE CALCULATOR",
            font=("Segoe UI", 11, "bold"), bg=PANEL, fg=GOLD
        ).pack(side="left", padx=12, pady=8)

        # --- Main content (two panels) ---
        body = tk.Frame(root, bg=BG)
        body.pack(fill="both", expand=True, padx=8, pady=(8, 0))

        self.your_frame = self._build_panel(body, "YOUR PETS", GREEN, 0)
        self.their_frame = self._build_panel(body, "TRADER'S PETS", BLUE, 1)

        # --- Result bar ---
        res_frame = tk.Frame(root, bg=PANEL, bd=0, highlightthickness=0)
        res_frame.pack(fill="x", padx=8, pady=8)

        self.result_lbl = tk.Label(
            res_frame, text="Add pets to both sides to compare values",
            font=("Segoe UI", 10, "bold"), bg=PANEL, fg=DIM, pady=8
        )
        self.result_lbl.pack(fill="x")

        tk.Label(
            root, text="Tip: press Enter in the Value field to add a pet",
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

    def _update_result(self):
        if not self.your_panel or not self.their_panel:
            return
        yours = self.your_panel.get_total()
        theirs = self.their_panel.get_total()
        diff = yours - theirs

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
