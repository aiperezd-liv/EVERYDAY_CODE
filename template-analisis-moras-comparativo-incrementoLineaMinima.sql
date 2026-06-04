/***********************************************************************************************************************
  PLANTILLA BASE: COMPARATIVA DE SALDOS Y MORAS (ESCENARIO OBSERVADO VS. ESCENARIO HIPOTÉTICO)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES (SE REMOVIÓ EL CÁLCULO PREMATURO DE NEW_LC)
------------------------------------------------------------------------------------------------------------------------
WITH LINEAS AS (
  SELECT
      BR_ING_TOT,              -- Ingreso total del cliente
      CTA_CVE,                 -- Clave única de la cuenta
      BR_IMP_LIM_CRED,         -- Límite de crédito asignado real (Observado en solicitud)
      BR_MODULO_SCORE_DES,     -- Descripción del módulo de score
      BR_HIT_DES,              -- Estatus de consulta en Buró (HIT / NOHIT / THIN FILE)
      SEGMENTO_SCORE,          -- Segmentación por score crediticio
      BR_NIVEL_RIESGO          -- Nivel de riesgo asignado
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2025-03-01' AND '2025-08-31'  -- <<< RANGO TEMPORAL PARA CUENTAS CON MAS DE 6 MESES DE ANTIGUEDAD
    AND BR_ORG = 210                                      -- <<< FILTRO DE PRODUCTO 
    AND CTA_CVE > 0                                       -- FILTRO CUENTAS ACTIVAS 
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: HISTÓRICO DE SALDOS MENSUALES Y MADURACIÓN (MOB).
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_NIV_MOR,       -- Nivel de mora en el mes (0 = Vigente, 1 = 1-30 días, etc.)
      a.CTA_SDO_ACT,       -- Saldo actual de la cuenta en ese corte mensual
      a.CTA_IMP_LIM_CRD,   -- Límite de crédito registrado en el mes
      b.CTA_FCH_ALTA,      -- Fecha en que se abrió la cuenta
      a.CTA_EDO_CVE,       -- Estado de la cuenta (Activa, Cancelada, etc.)
      DATE(a.ANIO, a.MES, 1) AS MES_OBS,
      
      -- Cálculo del MOB (Months On Books)
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210                           -- <<< FILTRO  DE PRODUCTO A EVALUAR 
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025                            -- Filtro temporal 
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: PIVOTEO DE COMPORTAMIENTO POR VENTANAS DE TIEMPO (MORAS)
------------------------------------------------------------------------------------------------------------------------
MORAS AS (
  SELECT
      CTA_CVE,
      CTA_FCH_ALTA,
      -- Ajuste solicitado: Si el comportamiento es del inicio (MOB <= 1) trae ese límite, si no, evalúa el máximo histórico de la cuenta
      COALESCE(
      MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
      MAX(CTA_IMP_LIM_CRD)) AS CTA_IMP_LIM_CRD,

      -- VENTANA 2 MESES (MOB = 2)
      MAX(CASE WHEN MOB = 2 THEN 1 ELSE 0 END) AS CTA_TOT_2M,
      MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
      MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN 1 ELSE 0 END) AS CTA_ENTRY_2M,     
      MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_ENTRY_2M,

      -- VENTANA 3 MESES (MOB = 3)
      MAX(CASE WHEN MOB = 3 THEN 1 ELSE 0 END) AS CTA_TOT_3M,
      MAX(CASE WHEN MOB = 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_3M,
      MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN 1 ELSE 0 END) AS CTA_30_3M,       
      MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_30_3M,    

      -- VENTANA 6 MESES (MOB = 6)
      MAX(CASE WHEN MOB = 6 THEN 1 ELSE 0 END) AS CTA_TOT_6M,
      MAX(CASE WHEN MOB = 6 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_6M,
      MAX(CASE WHEN MOB = 6 AND CTA_NIV_MOR >= 3 THEN 1 ELSE 0 END) AS CTA_30_6M,       
      MAX(CASE WHEN MOB = 6 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_30_6M,    

      -- VENTANA 9 MESES (MOB = 9)
      MAX(CASE WHEN MOB = 9 THEN 1 ELSE 0 END) AS CTA_TOT_9M,
      MAX(CASE WHEN MOB = 9 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_9M,
      MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN 1 ELSE 0 END) AS CTA_90_9M,        
      MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_90_9M,   

      -- VENTANA 12 MESES (MOB = 12)
      MAX(CASE WHEN MOB = 12 THEN 1 ELSE 0 END) AS CTA_TOT_12M,
      MAX(CASE WHEN MOB = 12 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_12M,
      MAX(CASE WHEN MOB = 12 AND CTA_NIV_MOR >= 5 THEN 1 ELSE 0 END) AS CTA_90_12M,      
      MAX(CASE WHEN MOB = 12 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_90_12M  
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1, 2
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3.5: CRUZE INTERMEDIO PARA PASAR LA REGLA DE NEGOCIO RECALCULADA CON EL LÍMITE DEL MÓDULO 3
------------------------------------------------------------------------------------------------------------------------
LINEAS_CON_NEW_LC AS (
  SELECT 
      a.*,
      b.CTA_IMP_LIM_CRD, 
      CASE 
        WHEN a.BR_ING_TOT >= 4000 AND b.CTA_IMP_LIM_CRD < 4000 THEN 4000 
        ELSE b.CTA_IMP_LIM_CRD
      END AS NEW_LC
  FROM LINEAS a
  JOIN MORAS b ON a.CTA_CVE = b.CTA_CVE
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: CÁLCULO DE MÉTRICAS PROMEDIO GRUPALES
------------------------------------------------------------------------------------------------------------------------
CALC_SDO_PROM AS (
  SELECT 
    a.BR_HIT_DES,
    a.SEGMENTO_SCORE,
    a.BR_NIVEL_RIESGO,
    a.NEW_LC,

    -- Tasas de morosidad grupales
    SAFE_DIVIDE(SUM(b.CTA_ENTRY_2M), SUM(b.CTA_TOT_2M)) AS BR_CTA_ENTRY_2M,
    SAFE_DIVIDE(SUM(b.CTA_30_3M), SUM(b.CTA_TOT_3M))   AS BR_CTA_30_3M,
    SAFE_DIVIDE(SUM(b.CTA_30_6M), SUM(b.CTA_TOT_6M))   AS BR_CTA_30_6M,
    SAFE_DIVIDE(SUM(b.CTA_90_9M), SUM(b.CTA_TOT_9M))   AS BR_CTA_90_9M,
    
    -- Porcentajes promedio de utilización de línea de crédito
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_ENTRY_2M, 0), b.CTA_IMP_LIM_CRD)) AS AVG_UTIL_ENTRY_2M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_TOT_2M, 0), b.CTA_IMP_LIM_CRD))   AS AVG_UTIL_TOT_2M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_TOT_3M, 0), b.CTA_IMP_LIM_CRD))   AS AVG_UTIL_TOT_3M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_30_3M, 0), b.CTA_IMP_LIM_CRD))    AS AVG_UTIL_30_3M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_TOT_6M, 0), b.CTA_IMP_LIM_CRD))   AS AVG_UTIL_TOT_6M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_30_6M, 0), b.CTA_IMP_LIM_CRD))    AS AVG_UTIL_30_6M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_TOT_9M, 0), b.CTA_IMP_LIM_CRD))   AS AVG_UTIL_TOT_9M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_90_9M, 0), b.CTA_IMP_LIM_CRD))    AS AVG_UTIL_90_9M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_TOT_12M, 0), b.CTA_IMP_LIM_CRD))  AS AVG_UTIL_TOT_12M,
    AVG(SAFE_DIVIDE(GREATEST(b.SDO_90_12M, 0), b.CTA_IMP_LIM_CRD))   AS AVG_UTIL_90_12M
  FROM LINEAS_CON_NEW_LC a
  JOIN MORAS b ON a.CTA_CVE = b.CTA_CVE
  GROUP BY 1, 2, 3, 4
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: MAESTRO CONSOLIDADO
------------------------------------------------------------------------------------------------------------------------
CONSOLIDADO AS (
  SELECT
     a.*,
     b.CTA_FCH_ALTA,
     b.CTA_TOT_2M,  b.SDO_TOT_2M,  b.CTA_ENTRY_2M,  b.SDO_ENTRY_2M,
     b.CTA_TOT_3M,  b.SDO_TOT_3M,  b.CTA_30_3M,     b.SDO_30_3M,
     b.CTA_TOT_6M,  b.SDO_TOT_6M,  b.CTA_30_6M,     b.SDO_30_6M,
     b.CTA_TOT_9M,  b.SDO_TOT_9M,  b.CTA_90_9M,     b.SDO_90_9M,
     b.CTA_TOT_12M, b.SDO_TOT_12M, b.CTA_90_12M,    b.SDO_90_12M,

     p.AVG_UTIL_ENTRY_2M, p.AVG_UTIL_TOT_2M, p.AVG_UTIL_TOT_3M, p.AVG_UTIL_30_3M,
     p.AVG_UTIL_TOT_6M,   p.AVG_UTIL_30_6M,   p.AVG_UTIL_TOT_9M,   p.AVG_UTIL_90_9M,
     p.AVG_UTIL_TOT_12M,  p.AVG_UTIL_90_12M,
     
     p.BR_CTA_ENTRY_2M,   p.BR_CTA_30_3M,     p.BR_CTA_30_6M,      p.BR_CTA_90_9M
  FROM LINEAS_CON_NEW_LC a
  JOIN MORAS b ON a.CTA_CVE = b.CTA_CVE
  LEFT JOIN CALC_SDO_PROM p
    ON p.BR_HIT_DES = a.BR_HIT_DES
   AND p.SEGMENTO_SCORE = a.SEGMENTO_SCORE
   AND p.BR_NIVEL_RIESGO = a.BR_NIVEL_RIESGO
   AND p.NEW_LC = a.NEW_LC
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 6: PROYECCIÓN DEL ESCENARIO HIPOTÉTICO (SIMULACIÓN DE SALDOS)
------------------------------------------------------------------------------------------------------------------------
NUEVAS_MORAS AS (
  SELECT
      *,
      DATE_TRUNC(CTA_FCH_ALTA, MONTH) AS COSECHA, 
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_TOT_2M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_TOT_2M * NEW_LC 
      END AS SDO_TOT_2M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_ENTRY_2M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_ENTRY_2M * NEW_LC * BR_CTA_ENTRY_2M 
      END AS SDO_ENTRY_2M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_TOT_3M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_TOT_3M * NEW_LC 
      END AS SDO_TOT_3M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_30_3M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_30_3M * NEW_LC * BR_CTA_30_3M 
      END AS SDO_30_3M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_TOT_6M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_TOT_6M * NEW_LC 
      END AS SDO_TOT_6M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_30_6M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_30_6M * NEW_LC * BR_CTA_30_6M 
      END AS SDO_30_6M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_TOT_9M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_TOT_9M * NEW_LC 
      END AS SDO_TOT_9M_NEW,
      
      CASE 
        WHEN CTA_IMP_LIM_CRD > 0 THEN SAFE_DIVIDE(GREATEST(SDO_90_9M, 0), CTA_IMP_LIM_CRD) * NEW_LC 
        ELSE AVG_UTIL_90_9M * NEW_LC * BR_CTA_90_9M 
      END AS SDO_90_9M_NEW
  FROM CONSOLIDADO
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 7: AGREGACIÓN POR VARIABLE DE APERTURA / SUBMUESTRA TARGET (ACTIVACIÓN DE BR_NIVEL_RIESGO)
------------------------------------------------------------------------------------------------------------------------
AGRUPADO AS (
  SELECT 
    BR_HIT_DES,
    BR_NIVEL_RIESGO, -- << VARIABLE COMPLETAMENTE ACTIVADA
    COUNT(*) AS Solicitudes,
    SUM(CASE WHEN CTA_CVE > 0 THEN 1 ELSE 0 END) AS Cuentas,

    -- NUEVAS MÉTRICAS: Líneas de crédito totales agregadas
    AVG(CTA_IMP_LIM_CRD) AS AVG_LC_ACT, 
    AVG(NEW_LC)          AS AVG_LC_NEW, 

    -- Totales agregados de saldos por escenario y ventana temporal
    SUM(SDO_TOT_2M_NEW)   AS SDO_TOT_2M_NEW,   SUM(SDO_TOT_2M)   AS SDO_TOT_2M_ACT,
    SUM(SDO_ENTRY_2M_NEW) AS SDO_ENTRY_2M_NEW, SUM(SDO_ENTRY_2M) AS SDO_ENTRY_2M_ACT,
    SUM(SUM(SDO_TOT_3M_NEW)) OVER(PARTITION BY BR_HIT_DES, BR_NIVEL_RIESGO), -- Nota: Se corrigieron los nombres de los sumatorios planos
    SUM(SDO_TOT_3M_NEW)   AS SDO_TOT_3M_NEW,   SUM(SDO_TOT_3M)   AS SDO_TOT_3M_ACT,
    SUM(SDO_30_3M_NEW)    AS SDO_30_3M_NEW,    SUM(SDO_30_3M)    AS SDO_30_3M_ACT,
    SUM(SDO_TOT_6M_NEW)   AS SDO_TOT_6M_NEW,   SUM(SDO_TOT_6M)   AS SDO_TOT_6M_ACT,
    SUM(SDO_30_6M_NEW)    AS SDO_30_6M_NEW,    SUM(SDO_30_6M)    AS SDO_30_6M_ACT,
    SUM(SDO_TOT_9M_NEW)   AS SDO_TOT_9M_NEW,   SUM(SDO_TOT_9M)   AS SDO_TOT_9M_ACT,
    SUM(SDO_90_9M_NEW)    AS SDO_90_9M_NEW,    SUM(SDO_90_9M)    AS SDO_90_9M_ACT
  FROM NUEVAS_MORAS
  WHERE BR_HIT_DES IN ('HIT', 'THIN FILE', 'NOHIT')  
  GROUP BY 1, 2 -- << SE AGREGA BR_NIVEL_RIESGO EN LA POSICIÓN 2 DE LA AGRUPACIÓN
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: REPORTE CON DESGLOSE DE CRUCE Y MÉTRICAS PROMEDIO
------------------------------------------------------------------------------------------------------------------------
SELECT 
  BR_HIT_DES,
  BR_NIVEL_RIESGO, -- << VARIABLE ACTIVADA EN EL REPORTE FINAL
  Solicitudes,
  Cuentas,

  -- METRICAS DE LÍNEAS DE CRÉDITO PROMEDIO
  AVG_LC_ACT,
  AVG_LC_NEW,

  -- ----------------------------------------------------
  -- VENTANA MOB 2M TOTAL
  -- ----------------------------------------------------
  SDO_TOT_2M_NEW, SDO_TOT_2M_ACT,
  (SDO_TOT_2M_NEW - SDO_TOT_2M_ACT) AS DIF_SDO_TOT_2M,
  SAFE_DIVIDE((SDO_TOT_2M_NEW - SDO_TOT_2M_ACT), SDO_TOT_2M_ACT) AS PORC_SDO_TOT_2M,

  -- ----------------------------------------------------
  -- VENTANA MOB 2M ENTRY (MORA TEMPRANA)
  -- ----------------------------------------------------
  SDO_ENTRY_2M_NEW, SDO_ENTRY_2M_ACT,
  (SDO_ENTRY_2M_NEW - SDO_ENTRY_2M_ACT) AS DIF_SDO_ENTRY_2M,
  SAFE_DIVIDE((SDO_ENTRY_2M_NEW - SDO_ENTRY_2M_ACT), SDO_ENTRY_2M_ACT) AS PORC_SDO_ENTRY_2M,

  -- ----------------------------------------------------
  -- VENTANA MOB 3M TOTAL
  -- ----------------------------------------------------
  SDO_TOT_3M_NEW, SDO_TOT_3M_ACT,
  (SDO_TOT_3M_NEW - SDO_TOT_3M_ACT) AS DIF_SDO_TOT_3M,
  SAFE_DIVIDE((SDO_TOT_3M_NEW - SDO_TOT_3M_ACT), SDO_TOT_3M_ACT) AS PORC_SDO_TOT_3M,

  -- ----------------------------------------------------
  -- VENTANA MOB 3M MORA 30+
  -- ----------------------------------------------------
  SDO_30_3M_NEW, SDO_30_3M_ACT,
  (SDO_30_3M_NEW - SDO_30_3M_ACT) AS DIF_SDO_30_3M,
  SAFE_DIVIDE((SDO_30_3M_NEW - SDO_30_3M_ACT), SDO_30_3M_ACT) AS PORC_SDO_30_3M,

  -- ----------------------------------------------------
  -- VENTANA MOB 6M TOTAL
  -- ----------------------------------------------------
  SDO_TOT_6M_NEW, SDO_TOT_6M_ACT,
  (SDO_TOT_6M_NEW - SDO_TOT_6M_ACT) AS DIF_SDO_TOT_6M,
  SAFE_DIVIDE((SDO_TOT_6M_NEW - SDO_TOT_6M_ACT), SDO_TOT_6M_ACT) AS PORC_SDO_TOT_6M,

  -- ----------------------------------------------------
  -- VENTANA MOB 6M MORA 30+
  -- ----------------------------------------------------
  SDO_30_6M_NEW, SDO_30_6M_ACT,
  (SDO_30_6M_NEW - SDO_30_6M_ACT) AS DIF_SDO_30_6M,
  SAFE_DIVIDE((SDO_30_6M_NEW - SDO_30_6M_ACT), SDO_30_6M_ACT) AS PORC_SDO_30_6M,

  -- ----------------------------------------------------
  -- VENTANA MOB 9M TOTAL
  -- ----------------------------------------------------
  SDO_TOT_9M_NEW, SDO_TOT_9M_ACT,
  (SDO_TOT_9M_NEW - SDO_TOT_9M_ACT) AS DIF_SDO_TOT_9M,
  SAFE_DIVIDE((SDO_TOT_9M_NEW - SDO_TOT_9M_ACT), SDO_TOT_9M_ACT) AS PORC_SDO_TOT_9M,

  -- ----------------------------------------------------
  -- VENTANA MOB 9M MORA MÁXIMA 90+
  -- ----------------------------------------------------
  SDO_90_9M_NEW, SDO_90_9M_ACT,
  (SDO_90_9M_NEW - SDO_90_9M_ACT) AS DIF_SDO_90_9M,
  SAFE_DIVIDE((SDO_90_9M_NEW - SDO_90_9M_ACT), SDO_90_9M_ACT) AS PORC_SDO_90_9M

FROM AGRUPADO
ORDER BY BR_HIT_DES, BR_NIVEL_RIESGO;
