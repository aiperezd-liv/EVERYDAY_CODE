-- ============================================================
-- PROPÓSITO: Extraer perfil sociodemográfico, consumo en MCCs educativos
--            (8211, 8220, 8241, 8244, 8249, 8299), utilización promedio
--            (MOB 1-12) y comportamiento de moras (Entry 2M, 30+ 3M, 90+ 9M)
--            para cuentas dadas de alta en 2024 y 2025 (BR_ORG = 200).
-- ============================================================

-- 1. UNIVERSO DE SOLICITUDES / CUENTAS (2024 y 2025, excluyendo 2026)
WITH CUENTAS_BASE AS (
  SELECT 
    sol.CTA_CVE,
    sol.DT_FCH_ALTA,
    MAX(sol.SC_RISK_LEVEL) AS SC_RISK_LEVEL,
    MAX(sol.BR_ING_TOT) AS BR_ING_TOT,
    MAX(sol.BR_IMP_LIM_CRED) AS BR_IMP_LIM_CRED
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES` sol
  WHERE sol.BR_ORG = 200
    AND sol.DT_FCH_ALTA BETWEEN '2024-01-01' AND '2025-12-31'
    AND sol.CTA_CVE IS NOT NULL
  GROUP BY 
    sol.CTA_CVE, 
    sol.DT_FCH_ALTA
),

-- 2. CRUCE CON TARJETAS ASOCIADAS A LA CUENTA
CUENTAS_TARJETAS AS (
  SELECT DISTINCT 
    base.CTA_CVE,
    base.DT_FCH_ALTA,
    trj.TRJ_NUM
  FROM CUENTAS_BASE base
  INNER JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA_TRJ` trj
    ON base.CTA_CVE = trj.CTA_CVE
),

-- 3. FILTRO Y AGREGACIÓN DE CONSUMO EN MCCs ESPECÍFICOS (PRIMEROS 12 MESES)
-- Selecciona únicamente cuentas con al menos 1 compra en los códigos solicitados
CONSUMO_GIRO_ESPECIFICO AS (
  SELECT 
    ct.CTA_CVE,
    COUNT(*) AS NUM_COMPRAS_GIRO,
    SUM(trn.IMP_LIQ) AS MONTO_TOTAL_GIRO,
    SAFE_DIVIDE(SUM(trn.IMP_LIQ), COUNT(*)) AS TICKET_PROMEDIO_GIRO
  FROM CUENTAS_TARJETAS ct
  INNER JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_TRN_A510` trn
    ON SAFE_CAST(ct.TRJ_NUM AS STRING) = trn.NUM_CTA
  WHERE SAFE_CAST(trn.MCC_CVE AS INT64) IN (
    8211, 
    8220
    ,8241
    ,8244
    ,8249
    ,8299
    )
    AND trn.FCH_CONSUMO >= ct.DT_FCH_ALTA
    AND trn.FCH_CONSUMO < DATE_ADD(ct.DT_FCH_ALTA, INTERVAL 12 MONTH)
    AND trn.FCH_CONSUMO <= '2025-12-31'
  GROUP BY 
    ct.CTA_CVE
),

-- 4. EXTRACCIÓN MENSUAL DE SALDOS, LÍMITES Y MORAS (2024 y 2025)
-- Se restringe a las cuentas que efectivamente compraron en el giro objetivo
SDO_CTA_MOB AS (
  SELECT 
    sdo.CTA_CVE,
    base.DT_FCH_ALTA,
    DATE_DIFF(DATE(sdo.ANIO, sdo.MES, 1), DATE_TRUNC(base.DT_FCH_ALTA, MONTH), MONTH) AS MOB,
    sdo.CTA_NIV_MOR,
    sdo.CTA_SDO_ACT,
    sdo.CTA_IMP_LIM_CRD
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` sdo
  INNER JOIN CUENTAS_BASE base
    ON sdo.CTA_CVE = base.CTA_CVE
  INNER JOIN CONSUMO_GIRO_ESPECIFICO giro
    ON sdo.CTA_CVE = giro.CTA_CVE
  WHERE sdo.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND sdo.ANIO IN (2024, 2025)
),

-- 5. PIVOTEO DE MORAS (ENTRY 2M, 30+ 3M, 90+ 9M), LÍMITE Y UTILIZACIÓN PROMEDIO (12M)
MORAS_Y_UTILIZACION AS (
  SELECT 
    CTA_CVE,
    -- Límite de crédito inicial (MOB <= 1) o máximo histórico observado
    COALESCE(
      MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END),
      MAX(CTA_IMP_LIM_CRD)
    ) AS CTA_IMP_LIM_CRD,

    -- Utilización promedio en los primeros 12 meses (MOB 1 a 12)
    AVG(
      CASE 
        WHEN MOB BETWEEN 1 AND 12 THEN SAFE_DIVIDE(GREATEST(CTA_SDO_ACT, 0), CTA_IMP_LIM_CRD) * 100.0
        ELSE NULL 
      END
    ) AS PORC_UTIL_PROM_12M,

    -- VENTANA 2 MESES: Entry (MOB = 2, Niv Mora >= 2)
    MAX(CASE WHEN MOB = 2 THEN 1 ELSE 0 END) AS CTA_TOT_2M,
    MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
    MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN 1 ELSE 0 END) AS CTA_ENTRY_2M,
    MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_ENTRY_2M,

    -- VENTANA 3 MESES: Mora 30+ (MOB = 3, Niv Mora >= 3)
    MAX(CASE WHEN MOB = 3 THEN 1 ELSE 0 END) AS CTA_TOT_3M,
    MAX(CASE WHEN MOB = 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_3M,
    MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN 1 ELSE 0 END) AS CTA_30_3M,
    MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_30_3M,

    -- VENTANA 9 MESES: Mora 90+ (MOB = 9, Niv Mora >= 5)
    MAX(CASE WHEN MOB = 9 THEN 1 ELSE 0 END) AS CTA_TOT_9M,
    MAX(CASE WHEN MOB = 9 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_9M,
    MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN 1 ELSE 0 END) AS CTA_90_9M,
    MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_90_9M
  FROM SDO_CTA_MOB
  GROUP BY 
    CTA_CVE
)

-- ============================================================
-- OUTPUT FINAL: Consolidado por cuenta con compras en MCCs objetivo
-- ============================================================
SELECT 
  base.CTA_CVE,
  base.DT_FCH_ALTA,
  EXTRACT(YEAR FROM base.DT_FCH_ALTA) AS ANIO_ALTA,
  base.SC_RISK_LEVEL,
  base.BR_ING_TOT,
  COALESCE(mu.CTA_IMP_LIM_CRD, base.BR_IMP_LIM_CRED) AS CTA_IMP_LIM_CRD,
  
  -- Métricas de consumo en los códigos MCC seleccionados
  giro.NUM_COMPRAS_GIRO,
  giro.MONTO_TOTAL_GIRO,
  giro.TICKET_PROMEDIO_GIRO,

  -- Utilización promedio primeros 12 meses
  mu.PORC_UTIL_PROM_12M,

  -- Métricas de Mora Entry (2M), 30+ (3M) y 90+ (9M)
  mu.CTA_TOT_2M,
  mu.SDO_TOT_2M,
  mu.CTA_ENTRY_2M,
  mu.SDO_ENTRY_2M,
  mu.CTA_TOT_3M,
  mu.SDO_TOT_3M,
  mu.CTA_30_3M,
  mu.SDO_30_3M,
  mu.CTA_TOT_9M,
  mu.SDO_TOT_9M,
  mu.CTA_90_9M,
  mu.SDO_90_9M
FROM CUENTAS_BASE base
INNER JOIN CONSUMO_GIRO_ESPECIFICO giro
  ON base.CTA_CVE = giro.CTA_CVE
LEFT JOIN MORAS_Y_UTILIZACION mu
  ON base.CTA_CVE = mu.CTA_CVE
ORDER BY 
  base.DT_FCH_ALTA,
  giro.MONTO_TOTAL_GIRO DESC
;
