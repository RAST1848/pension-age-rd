###############################################################################
#  RD_Edad_Pension_GEIH.R
#  Discontinuidad en la edad de pensión (57 mujeres / 62 hombres), GEIH 2024
#
#  Qué hace:
#   1. Lee los 12 meses de la GEIH (módulos Características generales,
#      Fuerza de trabajo y Ocupados) y los une por persona-mes.
#   2. Construye tasas ponderadas por edad simple y sexo: participación,
#      ocupación, ocupación formal (cotiza a pensión), informal y
#      "ocupado ya pensionado".
#   3. Estima el salto en el umbral con una regresión discontinua local
#      lineal (ancho de banda configurable) con errores robustos (HC0).
#   4. Corre placebos en edades sin umbral y en el umbral del otro sexo.
#   5. Exporta tablas (CSV) y gráficos (PNG) a la carpeta de salida.
#
#  Cómo correrlo: ajustar la sección CONFIGURACIÓN y presionar Run en VS Code.
#  Tiempo estimado: 2–5 minutos (no requiere el monitor de trabajos).
#  Solo usa base R; no requiere instalar paquetes.
###############################################################################

## ========================== CONFIGURACIÓN ================================ ##

# Carpeta raíz con una subcarpeta por mes (enero, febrero, ...), y dentro de
# cada una los CSV: caract_ss_edu.csv, fuerza_de_trabajo.csv, ocupados.csv
RAIZ_GEIH <- "C:/Datos/GEIH/geih_2024"

# Carpeta donde se guardan tablas y gráficos
CARPETA_SALIDA <- "C:/Datos/GEIH/salida_rd_pension"

# Separador y codificación de los CSV de DANE
SEP_CSV  <- ";"
ENCODING <- "latin1"

# Umbrales de edad de pensión (RPM/RAIS vigentes en 2024)
UMBRAL_HOMBRES <- 62
UMBRAL_MUJERES <- 57

# Rango de edades a graficar y anchos de banda (en años) para la RD
EDAD_MIN <- 45
EDAD_MAX <- 75
ANCHOS_BANDA <- c(3, 5, 8)

# Edades placebo (edades sin umbral + umbral del otro sexo)
PLACEBOS_HOMBRES <- c(57, 60, 65)
PLACEBOS_MUJERES <- c(62, 55, 60)

## ====================== 1. LECTURA Y UNIÓN DE MÓDULOS ==================== ##

cat("Leyendo GEIH desde:", RAIZ_GEIH, "\n")
dir.create(CARPETA_SALIDA, showWarnings = FALSE, recursive = TRUE)

LLAVE <- c("DIRECTORIO", "SECUENCIA_P", "ORDEN", "MES")

leer_modulo <- function(ruta, columnas) {
  # Lee solo las columnas necesarias para no cargar todo el archivo en memoria
  encabezado <- names(read.csv(ruta, sep = SEP_CSV, nrows = 1,
                               encoding = ENCODING, check.names = FALSE))
  tipos <- rep("NULL", length(encabezado))
  tipos[encabezado %in% columnas] <- NA
  tipos[encabezado == "MES"] <- "character"   # conservar "01", "02", ...
  read.csv(ruta, sep = SEP_CSV, colClasses = tipos,
           encoding = ENCODING, check.names = FALSE)
}

carpetas_mes <- list.dirs(RAIZ_GEIH, recursive = FALSE)
if (length(carpetas_mes) == 0) stop("No se encontraron subcarpetas de meses en RAIZ_GEIH")

lista_meses <- vector("list", length(carpetas_mes))
for (i in seq_along(carpetas_mes)) {
  carpeta <- carpetas_mes[i]
  cat("  ", basename(carpeta), "... ")
  car <- leer_modulo(file.path(carpeta, "caract_ss_edu.csv"),
                     c(LLAVE, "FEX_C18", "P3271", "P6040"))
  ft  <- leer_modulo(file.path(carpeta, "fuerza_de_trabajo.csv"),
                     c(LLAVE, "PET", "FT"))
  oc  <- leer_modulo(file.path(carpeta, "ocupados.csv"),
                     c(LLAVE, "OCI", "P6920"))
  d <- merge(car, ft, by = LLAVE, all.x = TRUE)
  d <- merge(d, oc, by = LLAVE, all.x = TRUE)
  d$archivo_mes <- basename(carpeta)
  lista_meses[[i]] <- d
  cat(nrow(d), "personas\n")
}
datos <- do.call(rbind, lista_meses)
rm(lista_meses, car, ft, oc, d)
cat("Total personas-mes:", nrow(datos), "\n\n")

## ===================== 2. VARIABLES DE RESULTADO ========================= ##

# P3271: 1 hombre, 2 mujer | P6040: edad | FEX_C18: factor de expansión
# FT: 1 = en la fuerza de trabajo | OCI: 1 = ocupado
# P6920 (solo ocupados): 1 cotiza a pensión, 2 no cotiza, 3 ya está pensionado
datos$edad  <- as.integer(datos$P6040)
datos$mujer <- as.integer(datos$P3271 == 2)
datos$w     <- datos$FEX_C18

es_ocupado <- !is.na(datos$OCI) & datos$OCI == 1
datos$ft       <- as.numeric(!is.na(datos$FT) & datos$FT == 1)
datos$ocu      <- as.numeric(es_ocupado)
datos$cotiza   <- as.numeric(es_ocupado & !is.na(datos$P6920) & datos$P6920 == 1)
datos$informal <- as.numeric(es_ocupado & !is.na(datos$P6920) & datos$P6920 == 2)
datos$ocu_pens <- as.numeric(es_ocupado & !is.na(datos$P6920) & datos$P6920 == 3)

RESULTADOS <- c("ft", "ocu", "cotiza", "informal", "ocu_pens")
ETIQUETAS  <- c(ft = "Participa en el mercado laboral",
                ocu = "Ocupado",
                cotiza = "Ocupado y cotiza a pensión (formal)",
                informal = "Ocupado sin cotizar (informal)",
                ocu_pens = "Ocupado y ya pensionado")

sub <- datos[datos$edad >= EDAD_MIN & datos$edad <= EDAD_MAX, ]

## ================ 3. TASAS PONDERADAS POR EDAD SIMPLE Y SEXO ============= ##

media_pond <- function(y, w) sum(y * w) / sum(w)

tasas <- aggregate(sub[, RESULTADOS], by = list(mujer = sub$mujer, edad = sub$edad),
                   FUN = function(x) NA)  # esqueleto; se llena abajo
for (k in seq_len(nrow(tasas))) {
  filas <- sub$mujer == tasas$mujer[k] & sub$edad == tasas$edad[k]
  tasas$n[k] <- sum(filas)
  for (y in RESULTADOS) tasas[k, y] <- media_pond(sub[filas, y], sub$w[filas])
}
tasas <- tasas[order(tasas$mujer, tasas$edad), c("mujer", "edad", "n", RESULTADOS)]

cat("==== Tasas por edad (hombres) ====\n")
print(round(tasas[tasas$mujer == 0, ], 3), row.names = FALSE)
cat("\n==== Tasas por edad (mujeres) ====\n")
print(round(tasas[tasas$mujer == 1, ], 3), row.names = FALSE)
write.csv(tasas, file.path(CARPETA_SALIDA, "tasas_por_edad_sexo.csv"), row.names = FALSE)

## ============ 4. REGRESIÓN DISCONTINUA LOCAL LINEAL (PONDERADA) ========== ##

# Modelo: y = a + b*(edad - c) + tau*1[edad >= c] + g*(edad - c)*1[edad >= c]
# estimado en la ventana [c - h, c + h - 1]; tau es el salto en el umbral.
# Error estándar robusto a heterocedasticidad (HC0) con pesos muestrales.
rd_local <- function(df, c, y, h) {
  x <- df[df$edad >= c - h & df$edad <= c + h - 1, ]
  z <- x$edad - c
  Tr <- as.numeric(z >= 0)
  X <- cbind(1, z, Tr, z * Tr)
  W <- x$w
  Xw <- X * W
  XtWX_inv <- solve(crossprod(X, Xw))
  beta <- XtWX_inv %*% crossprod(Xw, x[[y]])
  e <- as.vector(x[[y]] - X %*% beta)
  carne <- crossprod(Xw * e)
  V <- XtWX_inv %*% carne %*% XtWX_inv
  c(tau = beta[3], se = sqrt(V[3, 3]), n = nrow(x))
}

filas_rd <- list()
for (s in c(0, 1)) {
  c_umbral <- if (s == 0) UMBRAL_HOMBRES else UMBRAL_MUJERES
  placebos <- if (s == 0) PLACEBOS_HOMBRES else PLACEBOS_MUJERES
  df <- sub[sub$mujer == s, ]
  sexo <- if (s == 0) "Hombres" else "Mujeres"
  for (y in RESULTADOS) {
    for (h in ANCHOS_BANDA) {
      r <- rd_local(df, c_umbral, y, h)
      filas_rd[[length(filas_rd) + 1]] <- data.frame(
        sexo = sexo, tipo = "umbral", umbral = c_umbral, resultado = y, h = h,
        salto_pp = 100 * r["tau"], se_pp = 100 * r["se"], n = r["n"])
    }
  }
  # Placebos: participación con el ancho de banda intermedio
  h_pl <- ANCHOS_BANDA[ceiling(length(ANCHOS_BANDA) / 2)]
  for (cp in placebos) {
    r <- rd_local(df, cp, "ft", h_pl)
    filas_rd[[length(filas_rd) + 1]] <- data.frame(
      sexo = sexo, tipo = "placebo", umbral = cp, resultado = "ft", h = h_pl,
      salto_pp = 100 * r["tau"], se_pp = 100 * r["se"], n = r["n"])
  }
}
resultados_rd <- do.call(rbind, filas_rd)
rownames(resultados_rd) <- NULL
resultados_rd$t <- resultados_rd$salto_pp / resultados_rd$se_pp

cat("\n==== Saltos estimados en el umbral (puntos porcentuales) ====\n")
print(transform(resultados_rd, salto_pp = round(salto_pp, 1), se_pp = round(se_pp, 1),
                t = round(t, 1)), row.names = FALSE)
write.csv(resultados_rd, file.path(CARPETA_SALIDA, "resultados_rd.csv"), row.names = FALSE)

## ============================ 5. GRÁFICOS ================================ ##

COL_SERIE <- c(ft = "#2a78d6", cotiza = "#eb6834", informal = "#1baf7a")
COL_TEXTO <- "#898781"; COL_GRILLA <- "#e1e0d9"

graficar_panel <- function(s, c_umbral, titulo, edades = 50:70) {
  d <- tasas[tasas$mujer == s & tasas$edad %in% edades, ]
  plot(NA, xlim = range(edades), ylim = c(0, 100), axes = FALSE,
       xlab = "Edad (años cumplidos)", ylab = "% de la población de esa edad",
       main = titulo, adj = 0, col.lab = COL_TEXTO, col.main = "#0b0b0b")
  abline(h = seq(0, 100, 20), col = COL_GRILLA)
  abline(v = c_umbral - 0.5, col = COL_TEXTO, lty = 2)
  for (y in names(COL_SERIE)) {
    lines(d$edad, 100 * d[[y]], col = COL_SERIE[y], lwd = 2)
    points(d$edad, 100 * d[[y]], col = COL_SERIE[y], pch = 16, cex = 0.7)
  }
  axis(1, at = seq(min(edades), max(edades), 2), col = COL_GRILLA, col.axis = COL_TEXTO)
  axis(2, at = seq(0, 100, 20), col = NA, col.axis = COL_TEXTO, las = 1)
  text(c_umbral - 0.3, 97, paste("edad de pensión =", c_umbral),
       adj = c(0, 1), col = COL_TEXTO, cex = 0.8)
}

png(file.path(CARPETA_SALIDA, "rd_edad_pension.png"), width = 1800, height = 750, res = 150,
    bg = "#fcfcfb")
par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1), oma = c(3, 0, 0, 0), family = "sans")
graficar_panel(0, UMBRAL_HOMBRES, "Hombres — umbral 62")
graficar_panel(1, UMBRAL_MUJERES, "Mujeres — umbral 57")
par(fig = c(0, 1, 0, 1), oma = c(0, 0, 0, 0), mar = c(0, 0, 0, 0), new = TRUE)
plot(0, 0, type = "n", bty = "n", xaxt = "n", yaxt = "n")
legend("bottom", legend = ETIQUETAS[names(COL_SERIE)], col = COL_SERIE, lwd = 2, pch = 16,
       horiz = TRUE, bty = "n", cex = 0.8, text.col = "#0b0b0b")
dev.off()

# Gráfico de "ocupado ya pensionado" (la imagen espejo del salto)
png(file.path(CARPETA_SALIDA, "rd_ocupado_pensionado.png"), width = 1800, height = 750, res = 150,
    bg = "#fcfcfb")
par(mfrow = c(1, 2), mar = c(4.5, 4.5, 3, 1))
for (s in c(0, 1)) {
  c_umbral <- if (s == 0) UMBRAL_HOMBRES else UMBRAL_MUJERES
  d <- tasas[tasas$mujer == s & tasas$edad %in% 50:70, ]
  plot(d$edad, 100 * d$ocu_pens, type = "b", pch = 16, lwd = 2, col = "#6250d6",
       ylim = c(0, 10), axes = FALSE, xlab = "Edad (años cumplidos)",
       ylab = "% ocupados que ya reciben pensión",
       main = if (s == 0) "Hombres — umbral 62" else "Mujeres — umbral 57", adj = 0)
  abline(h = seq(0, 10, 2), col = COL_GRILLA)
  abline(v = c_umbral - 0.5, col = COL_TEXTO, lty = 2)
  axis(1, at = seq(50, 70, 2), col = COL_GRILLA, col.axis = COL_TEXTO)
  axis(2, at = seq(0, 10, 2), col = NA, col.axis = COL_TEXTO, las = 1)
}
dev.off()

cat("\nListo. Salidas en:", CARPETA_SALIDA, "\n")
