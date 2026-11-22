"""Imagen final para LinkedIn: 1200x900, título y fuente dentro de la imagen."""
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

t = pd.read_csv("tasas_por_edad_sexo.csv")
SURF, MUTED, GRID, TXT = "#fcfcfb", "#898781", "#e1e0d9", "#0b0b0b"
C1, C2, C3 = "#2a78d6", "#eb6834", "#1baf7a"

fig, axes = plt.subplots(1, 2, figsize=(12, 9), sharey=True, facecolor=SURF)
for ax, s, c, titulo in [(axes[0], 0, 62, "Men"), (axes[1], 1, 57, "Women")]:
    d = t[(t["mujer"] == s) & (t["edad"] >= 50) & (t["edad"] <= 70)]
    ax.set_facecolor(SURF)
    ax.axvspan(c - 0.5, 70.5, color="#f1f0ec", zorder=0)
    ax.axvline(c - 0.5, color=MUTED, lw=1.2, ls="--")
    ax.plot(d["edad"], 100 * d["ft"], color=C1, lw=2.6, marker="o", ms=5)
    ax.plot(d["edad"], 100 * d["cotiza"], color=C2, lw=2.6, marker="o", ms=5)
    ax.plot(d["edad"], 100 * d["informal"], color=C3, lw=2.6, marker="o", ms=5)
    # etiquetas directas al final de cada línea
    ult = d[d["edad"] == 70].iloc[0]
    for y, col, lab in ([] if s == 1 else [("ft", C1, "In the\nlabor force"),
                        ("cotiza", C2, "Employed, contributing\nto pension (formal)"),
                        ("informal", C3, "Employed, not\ncontributing (informal)")]):
        ax.annotate(lab, (70, 100 * ult[y]), xytext=(6, 0), textcoords="offset points",
                    color=TXT, fontsize=10.5, va="center")
    ax.set_title(titulo, loc="left", color=TXT, fontsize=16, fontweight="bold", pad=10)
    ax.text(c - 0.3, 98.5, f"Pension age: {c}", color=TXT, fontsize=11, va="top", fontweight="bold")
    ax.set_xlabel("Age (completed years)", color=MUTED, fontsize=11)
    ax.set_xticks(range(50, 71, 4)); ax.set_xlim(49.5, 70.5)
    ax.tick_params(colors=MUTED, labelsize=11)
    for sp in ["top", "right", "left"]:
        ax.spines[sp].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.grid(axis="y", color=GRID, lw=0.8); ax.set_axisbelow(True)

# anotación del salto en hombres
dh = t[(t["mujer"] == 0)].set_index("edad")["ft"]
axes[0].annotate("", xy=(62, 100 * dh[62]), xytext=(62, 100 * dh[61]),
                 arrowprops=dict(arrowstyle="<->", color=TXT, lw=1.4))
axes[0].text(62.6, 100 * (dh[61] + dh[62]) / 2, f"{100*dh[61]:.0f}% to {100*dh[62]:.0f}%\nin a single year",
             color=TXT, fontsize=10.5, va="center")

axes[0].set_ylabel("% of population at that age", color=MUTED, fontsize=11)
axes[0].set_ylim(0, 100)
fig.suptitle("Labor-force participation by exact age, Colombia 2024", x=0.04, y=0.98, ha="left",
             color=TXT, fontsize=20, fontweight="bold")
fig.text(0.04, 0.915, "The drop at the pension age is entirely formal employment; informal work does not react.",
         color="#52514e", fontsize=12.5)
fig.text(0.04, 0.02, "Source: DANE, GEIH 2024 (12 months pooled, survey-weighted). Formal = employed and contributing to pension. "
         "Own calculations; personal analysis.", color=MUTED, fontsize=9.5)
h = [plt.Line2D([], [], color=c, lw=2.6, marker="o", ms=5) for c in (C1, C2, C3)]
fig.legend(h, ["In the labor force", "Employed, contributing to pension (formal)", "Employed, not contributing (informal)"],
           loc="lower center", ncol=3, frameon=False, fontsize=11, bbox_to_anchor=(0.5, 0.045))
fig.tight_layout(rect=[0, 0.085, 0.98, 0.92], w_pad=5)
fig.savefig("linkedin_post_image.png", dpi=100, facecolor=SURF)
