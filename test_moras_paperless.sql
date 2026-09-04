-- ============================================================
-- PROPÓSITO: Calcular las 3 moras en saldos por MOB (2M Entry, 3M 30+, 9M 90+)
--            para la Tarjeta (BR_ORG = 210) dentro del Canal TRADICIONAL,
--            comparando subgrupos de Estado de Cuenta Digital vs Físico/Papel.
-- ============================================================

-- STREAMING_CHUNK: Filtrado de solicitudes aperturadas en Canal Tradicional y nivel de riesgo...
WITH SOLICITUDES_TRADICIONAL AS (
  SELECT DISTINCT
    CTA_CVE,
    BR_ORG,
    UPPER(SC_RISK_LEVEL) AS SC_RISK_LEVEL
  FROM `crp-dev-dominio-negfin.mus_dev_orig_crd_wrk_tbls.TMP_FAC_SOLICITUDES`
  WHERE CTA_CVE > 0
    AND CANAL NOT IN ('OCDT', 'OD_MODULO', 'OD_TABLET')
    AND BR_ORG = 210
),

-- STREAMING_CHUNK: Obteniendo la fecha de alta desde VDIM_CTA y filtrando originación 2025...
CUENTAS_BASE AS (
  SELECT 
    dim.CTA_CVE,
    dim.CTA_FCH_ALTA
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` dim
  INNER JOIN SOLICITUDES_TRADICIONAL sol
    ON dim.CTA_CVE = sol.CTA_CVE
  WHERE dim.CTA_CVE > 0
    AND dim.CTA_FCH_ALTA >= '2025-01-01'
    AND dim.CTA_FCH_ALTA <= '2025-12-31'
),

-- STREAMING_CHUNK: Única lectura consolidada de VFAC_SDO_CTA_MES para cálculo de MOB y estado de cuenta...
SDO_CON_MOB AS (
  SELECT
    sdo.CTA_CVE,
    sdo.ANIO,
    sdo.MES,
    sdo.CTA_STMT_FLG,
    DATE_DIFF(DATE(sdo.ANIO, sdo.MES, 1), DATE_TRUNC(cta.CTA_FCH_ALTA, MONTH), MONTH) AS MOB,
    sdo.CTA_NIV_MOR,
    sdo.CTA_SDO_ACT
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` sdo
  INNER JOIN CUENTAS_BASE cta 
    ON sdo.CTA_CVE = cta.CTA_CVE
  WHERE sdo.CTA_CVE > 0
    AND sdo.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    -- AND ANIO = 2025
    -- AND MES = 12
),

-- STREAMING_CHUNK: Evaluación de comportamientos por MOB y extracción del tipo de estado de cuenta...
COMPORTAMIENTO_CUENTAS AS (
  SELECT
    CTA_CVE,
    
    -- Clasificación de Estado de Cuenta capturada en MOB 1 (primer estado registrado)
    COALESCE(
      MAX(CASE WHEN MOB = 1 THEN CASE WHEN TRIM(CTA_STMT_FLG) IN ('1') THEN 'Digital' ELSE 'Físico / Papel' END END),
      MAX(CASE WHEN TRIM(CTA_STMT_FLG) IN ('1')  THEN 'Digital' ELSE 'Físico / Papel' END)
    ) AS TIPO_EDO_CUENTA,

    -- VENTANA 2 MESES (MOB = 2: Mora Temprana Entry)
    MAX(CASE WHEN MOB = 2 THEN 1 ELSE 0 END) AS CTA_TOT_2M,
    MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
    MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN 1 ELSE 0 END) AS CTA_ENTRY_2M,     
    MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_ENTRY_2M,

    -- VENTANA 3 MESES (MOB = 3: Mora 30+)
    MAX(CASE WHEN MOB = 3 THEN 1 ELSE 0 END) AS CTA_TOT_3M,
    MAX(CASE WHEN MOB = 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_3M,
    MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN 1 ELSE 0 END) AS CTA_30_3M,        
    MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_30_3M,    

    -- VENTANA 6 MESES (MOB = 6: Mora 30+)
    MAX(CASE WHEN MOB = 6 THEN 1 ELSE 0 END) AS CTA_TOT_6M,
    MAX(CASE WHEN MOB = 6 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_6M,
    MAX(CASE WHEN MOB = 6 AND CTA_NIV_MOR >= 3 THEN 1 ELSE 0 END) AS CTA_30_6M,        
    MAX(CASE WHEN MOB = 6 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_30_6M,    

    -- VENTANA 9 MESES (MOB = 9: Mora 90+)
    MAX(CASE WHEN MOB = 9 THEN 1 ELSE 0 END) AS CTA_TOT_9M,
    MAX(CASE WHEN MOB = 9 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_9M,
    MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN 1 ELSE 0 END) AS CTA_90_9M,        
    MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_90_9M,   

    -- VENTANA 12 MESES (MOB = 12: Mora 90+)
    MAX(CASE WHEN MOB = 12 THEN 1 ELSE 0 END) AS CTA_TOT_12M,
    MAX(CASE WHEN MOB = 12 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_12M,
    MAX(CASE WHEN MOB = 12 AND CTA_NIV_MOR >= 5 THEN 1 ELSE 0 END) AS CTA_90_12M,      
    MAX(CASE WHEN MOB = 12 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_90_12M
  FROM SDO_CON_MOB
  GROUP BY CTA_CVE
),

-- STREAMING_CHUNK: Unificación de información con solicitudes...
UNIFIED_DATA AS (
  SELECT 
    cmp.CTA_CVE,
    COALESCE(sol.SC_RISK_LEVEL, 'SIN INFORMACION') AS SC_RISK_LEVEL,
    COALESCE(cmp.TIPO_EDO_CUENTA, 'Físico / Papel') AS TIPO_EDO_CUENTA,
    
    -- Cuentas y Saldos 2M
    cmp.CTA_TOT_2M,
    cmp.SDO_TOT_2M,
    cmp.CTA_ENTRY_2M,
    cmp.SDO_ENTRY_2M,

    -- Cuentas y Saldos 3M
    cmp.CTA_TOT_3M,
    cmp.SDO_TOT_3M,
    cmp.CTA_30_3M,
    cmp.SDO_30_3M,

    -- Cuentas y Saldos 6M
    cmp.CTA_TOT_6M,
    cmp.SDO_TOT_6M,
    cmp.CTA_30_6M,
    cmp.SDO_30_6M,

    -- Cuentas y Saldos 9M
    cmp.CTA_TOT_9M,
    cmp.SDO_TOT_9M,
    cmp.CTA_90_9M,
    cmp.SDO_90_9M,

    -- Cuentas y Saldos 12M
    cmp.CTA_TOT_12M,
    cmp.SDO_TOT_12M,
    cmp.CTA_90_12M,
    cmp.SDO_90_12M
  FROM COMPORTAMIENTO_CUENTAS cmp
  INNER JOIN SOLICITUDES_TRADICIONAL sol
    ON cmp.CTA_CVE = sol.CTA_CVE
)

-- STREAMING_CHUNK: Resumen agrupado final con ratios por cuentas y saldos...
SELECT
  SC_RISK_LEVEL,
  TIPO_EDO_CUENTA,
  COUNT(DISTINCT CTA_CVE) AS TOTAL_CUENTAS,
  
  -- MOB 2: Mora Temprana Entry
  -- SUM(CTA_TOT_2M) AS CTA_TOT_2M,
  -- SUM(CTA_ENTRY_2M) AS CTA_ENTRY_2M,
  SAFE_DIVIDE(SUM(CTA_ENTRY_2M), SUM(CTA_TOT_2M)) AS RATIO_ENTRY_AT_2MOB_CTA,
  -- SUM(SDO_TOT_2M) AS SDO_TOT_2M,
  -- SUM(SDO_ENTRY_2M) AS SDO_ENTRY_2M,
  SAFE_DIVIDE(SUM(SDO_ENTRY_2M), SUM(SDO_TOT_2M)) AS RATIO_ENTRY_AT_2MOB_SDO,
  
  -- MOB 3: Mora 30+
  -- SUM(CTA_TOT_3M) AS CTA_TOT_3M,
  -- SUM(CTA_30_3M) AS CTA_30_3M,
  SAFE_DIVIDE(SUM(CTA_30_3M), SUM(CTA_TOT_3M)) AS RATIO_30_PLUS_AT_3MOB_CTA,
  -- SUM(SDO_TOT_3M) AS SDO_TOT_3M,
  -- SUM(SDO_30_3M) AS SDO_30_3M,
  SAFE_DIVIDE(SUM(SDO_30_3M), SUM(SDO_TOT_3M)) AS RATIO_30_PLUS_AT_3MOB_SDO,

  -- MOB 9: Mora 90+
  -- SUM(CTA_TOT_9M) AS CTA_TOT_9M,
  -- SUM(CTA_90_9M) AS CTA_90_9M,
  SAFE_DIVIDE(SUM(CTA_90_9M), SUM(CTA_TOT_9M)) AS RATIO_90_PLUS_AT_9MOB_CTA,
  -- SUM(SDO_TOT_9M) AS SDO_TOT_9M,
  -- SUM(SDO_90_9M) AS SDO_90_9M,
  SAFE_DIVIDE(SUM(SDO_90_9M), SUM(SDO_TOT_9M)) AS RATIO_90_PLUS_AT_9MOB_SDO,

FROM UNIFIED_DATA
WHERE SC_RISK_LEVEL NOT IN ('0. NO IDENTIFICADO', 'SIN INFORMACION', '6. SWAP-IN')
GROUP BY SC_RISK_LEVEL, TIPO_EDO_CUENTA
ORDER BY SC_RISK_LEVEL, TIPO_EDO_CUENTA;
