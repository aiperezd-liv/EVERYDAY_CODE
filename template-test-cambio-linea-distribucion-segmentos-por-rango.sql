/***********************************************************************************************************************
  PERFILAMIENTO DE PORTAFOLIO: DISTRIBUCIÓN PORCENTUAL DE CUENTAS POR RANGO DE LÍNEA DE CRÉDITO (RANGOS AMPLIADOS)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: UNIVERSO DE CUENTAS ACTIVAS Y ASIGNACIÓN DE SU RANGO DE LÍNEA ACTUAL
------------------------------------------------------------------------------------------------------------------------
WITH UNIVERSO_LINEAS AS (
  SELECT
      a.CTA_CVE,
      a.BR_HIT_DES,
      a.BR_ING_TOT,
      b.CTA_IMP_LIM_CRD,
      
      -- Clasificación exacta incluyendo el nuevo rango de 15K a 20K
      CASE 
        WHEN a.BR_ING_TOT >= 4000 AND b.CTA_IMP_LIM_CRD < 4000 THEN 'a. Mínima Target (Ing>=4k | LC<4k)'
        WHEN b.CTA_IMP_LIM_CRD < 4000                          THEN 'b. [Mínima, 4000) General'
        WHEN b.CTA_IMP_LIM_CRD >= 4000  AND b.CTA_IMP_LIM_CRD < 6000  THEN 'c. [4000, 6000)'
        WHEN b.CTA_IMP_LIM_CRD >= 6000  AND b.CTA_IMP_LIM_CRD < 8000  THEN 'd. [6000, 8000)'
        WHEN b.CTA_IMP_LIM_CRD >= 8000  AND b.CTA_IMP_LIM_CRD < 10000 THEN 'e. [8000, 10000)'
        WHEN b.CTA_IMP_LIM_CRD >= 10000 AND b.CTA_IMP_LIM_CRD < 15000 THEN 'f. [10000, 15000)'
        WHEN b.CTA_IMP_LIM_CRD >= 15000 AND b.CTA_IMP_LIM_CRD < 20000 THEN 'g. [15000, 20000)' -- <-- Nuevo Rango Solicitado
        WHEN b.CTA_IMP_LIM_CRD >= 20000                               THEN 'h. [20000, o más)'
        ELSE 'i. Otros / Fuera de Rango'
      END AS RANGO_LINEA
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES` a
  
  -- Traemos el límite real final agrupado por cuenta desde el histórico mensual de saldos
  JOIN (
    SELECT 
      CTA_CVE,
      MAX(CTA_IMP_LIM_CRD) AS CTA_IMP_LIM_CRD
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES`
    WHERE TIP_INF = 210
      AND CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
      AND ANIO >= 2025
    GROUP BY 1
  ) b ON a.CTA_CVE = b.CTA_CVE

  WHERE a.DT_FCH_SOL BETWEEN '2025-03-01' AND '2025-08-31'
    AND a.BR_ORG = 210
    AND a.CTA_CVE > 0
    AND a.BR_HIT_DES IN ('HIT', 'NOHIT') -- Sin Thin File
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: CONTEO ABSOLUTO DE CUENTAS POR RANGO Y TIPO DE BURÓ
------------------------------------------------------------------------------------------------------------------------
CONTEOS AS (
  SELECT 
    RANGO_LINEA,
    COUNT(CASE WHEN BR_HIT_DES = 'HIT' THEN 1 END) AS CUENTAS_HIT,
    COUNT(CASE WHEN BR_HIT_DES = 'NOHIT' THEN 1 END) AS CUENTAS_NOHIT,
    COUNT(*) AS CUENTAS_TOTALES
  FROM UNIVERSO_LINEAS
  GROUP BY 1
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: TOTALIZADORES VERTICALES PARA EL CÁLCULO DEL % (DENOMINADORES)
------------------------------------------------------------------------------------------------------------------------
TOTALES_UNIVERSO AS (
  SELECT 
    SUM(CUENTAS_HIT) AS GRAN_TOTAL_HIT,
    SUM(CUENTAS_NOHIT) AS GRAN_TOTAL_NOHIT,
    SUM(CUENTAS_TOTALES) AS GRAN_TOTAL_GENERAL
  FROM CONTEOS
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: MATRIZ DE DISTRIBUCIÓN PORCENTUAL (SUMA 100% HACIA ABAJO EN CADA COLUMNA)
------------------------------------------------------------------------------------------------------------------------
SELECT 
  c.RANGO_LINEA,
  
  -- Volúmenes Absolutos
  c.CUENTAS_HIT,
  c.CUENTAS_NOHIT,
  c.CUENTAS_TOTALES AS TOTAL_COMBINADO,

  -- Distribución Porcentual Vertical
  SAFE_DIVIDE(c.CUENTAS_HIT, t.GRAN_TOTAL_HIT) AS PORC_DIST_HIT,
  SAFE_DIVIDE(c.CUENTAS_NOHIT, t.GRAN_TOTAL_NOHIT) AS PORC_DIST_NOHIT,
  SAFE_DIVIDE(c.CUENTAS_TOTALES, t.GRAN_TOTAL_GENERAL) AS PORC_DIST_TOTAL_GENERAL

FROM CONTEOS c
CROSS JOIN TOTALES_UNIVERSO t
ORDER BY c.RANGO_LINEA;
