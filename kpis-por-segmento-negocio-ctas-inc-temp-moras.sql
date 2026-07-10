/***********************************************************************************************************************
  SCRIPT DE PORTAFOLIO FINAL: VARIABLES DE MORA POST-INCREMENTO (SÓLO VISA - BR_ORG = 200)
  MÉTRICAS: Ratios de Mora Fijos Tradicionales vs Ratios Relativos Indexados al Incremento (Mes de Incremento = MOB 0)
  FILTRO: Cuentas con Incremento de Línea (INC_TEMP = 1) ocurridos estrictamente entre MOB 9 y MOB 12.
  CORRECCIÓN: Se elimina ambigüedad en Joins usando "ON" explícito y se comentan variables de saldo absoluto.
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: UNIVERSO BASE DE SOLICITUDES (ENERO - SEPTIEMBRE 2024 / EXCLUSIVO BR_ORG = 200)
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES AS (
  SELECT
      CTA_CVE,
      BR_SOLIC_CVE,
      BR_ORG
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2024-01-01' AND '2024-09-30'
    AND BR_ORG = 200
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: DATOS DEMOGRÁFICOS BASE (MAPEO CORREGIDO M=MASCULINO / F=FEMENINO)
------------------------------------------------------------------------------------------------------------------------
DEMOGRAFICOS AS (
  SELECT * FROM (
    SELECT 
        BR_SOLIC_CVE,
        BR_EDAD,
        CASE 
          WHEN TRIM(UPPER(BR_SEXO)) IN ('FEMENINO', 'F')   THEN 'M' -- 'M' de segmentación interna (Mujer)
          WHEN TRIM(UPPER(BR_SEXO)) IN ('MASCULINO', 'M')  THEN 'H' -- 'H' de segmentación interna (Hombre)
          ELSE 'DESCONOCIDO'
        END AS BR_GENERO
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_APIA`
  )
  WHERE BR_GENERO IN ('M', 'H')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: MATRIZ DE CATÁLOGOS POR EDAD Y GÉNERO
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CATALOGOS AS (
  SELECT 
      s.*, 
      COALESCE(d.BR_EDAD, 0) AS BR_EDAD,
      d.BR_GENERO,
      CASE 
        WHEN d.BR_EDAD BETWEEN 18 AND 24                        THEN 'Gen Z'
        WHEN d.BR_EDAD BETWEEN 25 AND 35 AND d.BR_GENERO = 'M' THEN 'Chava Free Spirit'
        WHEN d.BR_EDAD BETWEEN 25 AND 35 AND d.BR_GENERO = 'H' THEN 'Soltero tecnológico'
        WHEN d.BR_EDAD BETWEEN 36 AND 50 AND d.BR_GENERO = 'M' THEN 'Mamá práctica'
        WHEN d.BR_EDAD BETWEEN 36 AND 60 AND d.BR_GENERO = 'H' THEN 'Jefe de familia'
        WHEN d.BR_EDAD BETWEEN 51 AND 60 AND d.BR_GENERO = 'M' THEN 'Señora generosa'
        WHEN d.BR_EDAD >= 61                                   THEN 'Adultos mayores'
        ELSE 'Segmento Sin Datos'
      END AS CATALOGO
  FROM SOLICITUDES s
  LEFT JOIN DEMOGRAFICOS d 
     ON s.BR_SOLIC_CVE = d.BR_SOLIC_CVE
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: COMPORTAMIENTO MENSUAL - HISTÓRICO COMPLETO DE CUENTAS (RESTRINGIDO A LOS PRIMEROS 12 MESES)
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_SDO_ACT,
      a.CTA_NIV_MOR,       
      a.CTA_IMP_LIM_CRD,   -- Límite Actual
      a.CTA_LAST_LIM_CRE,  -- Límite Anterior
      b.CTA_FCH_ALTA,   
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b 
    ON a.CTA_CVE = b.CTA_CVE -- Corrección: Uso explícito de ON
  WHERE a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2024 
    AND DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) BETWEEN 0 AND 12
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: CUENTAS TARGET Y ETIQUETAS 
------------------------------------------------------------------------------------------------------------------------
CUENTAS_TARGET AS (
  SELECT
      CTA_CVE,
      MAX(CASE WHEN CTA_LAST_LIM_CRE > 0 AND CTA_IMP_LIM_CRD > CTA_LAST_LIM_CRE THEN 1 ELSE 0 END) AS INC_TEMP,
      MAX(CASE WHEN CTA_LAST_LIM_CRE > 0 AND CTA_IMP_LIM_CRD > CTA_LAST_LIM_CRE THEN MOB END) AS MOB_INC
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1
),

------------------------------------------------------------------------------------------------------------------------
-- PASO INTERMEDIO: FILTRAR TARGET POR LA VENTANA SOLICITADA (9 A 12)
------------------------------------------------------------------------------------------------------------------------
PASO_INTERMEDIO_INC AS (
  SELECT 
      CTA_CVE,
      INC_TEMP,
      MOB_INC
  FROM CUENTAS_TARGET
  WHERE MOB_INC BETWEEN 9 AND 12
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 6: INNER JOIN CON SDO_CTA_MES COMPLETO (ARREGLADO PARA EVITAR AMBIGÜEDAD)
------------------------------------------------------------------------------------------------------------------------
COMPORTAMIENTO_HISTORICO AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_SDO_ACT,
      a.CTA_NIV_MOR,
      inc.INC_TEMP AS ETIQUETA_INC_TEMP, -- Alias claro para evitar cualquier ambigüedad posterior
      inc.MOB_INC AS ETIQUETA_MOB_INC,   -- Alias claro para evitar cualquier ambigüedad posterior
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  INNER JOIN PASO_INTERMEDIO_INC inc 
    ON a.CTA_CVE = inc.CTA_CVE  -- Inner Join corregido con ON explícito
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b 
    ON a.CTA_CVE = b.CTA_CVE  -- Left Join corregido con ON explícito
  WHERE a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2024
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 7: PIVOTEO FINANCIERO (CON CODIFICACIÓN LIMPIA Y SEGURO CONTRA ERRORES)
------------------------------------------------------------------------------------------------------------------------
PIVOTEO_FINANCIERO AS (
  SELECT
      CTA_CVE,
      MAX(ETIQUETA_INC_TEMP) AS INC_TEMP,
      MAX(ETIQUETA_MOB_INC) AS MOB_INC,

      -- 1. EVALUACIONES TRADICIONALES FIJAS (DESDE ORIGINACIÓN)
      MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
      MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_2M,

      MAX(CASE WHEN MOB = 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_3M,
      MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_3M,

      MAX(CASE WHEN MOB = 9 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_9M,
      MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_9M,

      -- 2. EVALUACIONES RELATIVAS POST-INCREMENTO (INDEXACIÓN A MES 0)
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 2) THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_POST_2M,
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 2) AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_POST_2M,

      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 3) THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_POST_3M,
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 3) AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_POST_3M,

      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 9) THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_POST_9M,
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC + 9) AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_POST_9M

  FROM COMPORTAMIENTO_HISTORICO
  GROUP BY 1
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: EXTRACCIÓN AGRUPADA EXCLUSIVA DE RATIOS (SALDOS COMENTADOS)
------------------------------------------------------------------------------------------------------------------------
SELECT
    c.CATALOGO,
    COUNT(DISTINCT c.CTA_CVE) AS NUMERO_CUENTAS,
    
    -- =========================================================================
    -- BLOQUE A: MEDIDAS TRADICIONALES FIJAS (DESDE ORIGINACIÓN)
    -- =========================================================================
    -- SUM(pf.SDO_TOT_2M) AS SDO_TOT_TRAD_MOB2,
    -- SUM(pf.SDO_MORA_2M) AS SDO_MORA_TRAD_MOB2,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_2M), SUM(pf.SDO_TOT_2M)) AS RATIO_TRAD_ENTRY_AT_2MOB,
    
    -- SUM(pf.SDO_TOT_3M) AS SDO_TOT_TRAD_MOB3,
    -- SUM(pf.SDO_MORA_3M) AS SDO_MORA_TRAD_MOB3,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_3M), SUM(pf.SDO_TOT_3M)) AS RATIO_TRAD_30PLUS_AT_3MOB,
    
    -- SUM(pf.SDO_TOT_9M) AS SDO_TOT_TRAD_MOB9,
    -- SUM(pf.SDO_MORA_9M) AS SDO_MORA_TRAD_MOB9,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_9M), SUM(pf.SDO_TOT_9M)) AS RATIO_TRAD_90PLUS_AT_9MOB,

    -- =========================================================================
    -- BLOQUE B: MEDIDAS RELATIVAS EVOLUTIVAS (POST-INCREMENTO REAL)
    -- =========================================================================
    -- SUM(pf.SDO_TOT_POST_2M) AS SDO_TOT_POST_INC_2M,
    -- SUM(pf.SDO_MORA_POST_2M) AS SDO_MORA_POST_INC_2M,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_POST_2M), SUM(pf.SDO_TOT_POST_2M)) AS RATIO_POST_INC_ENTRY_2M,
    
    -- SUM(pf.SDO_TOT_POST_3M) AS SDO_TOT_POST_INC_3M,
    -- SUM(pf.SDO_MORA_POST_3M) AS SDO_MORA_POST_INC_3M,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_POST_3M), SUM(pf.SDO_TOT_POST_3M)) AS RATIO_POST_INC_30PLUS_3M,
    
    -- SUM(pf.SDO_TOT_POST_9M) AS SDO_TOT_POST_INC_9M,
    -- SUM(pf.SDO_MORA_POST_9M) AS SDO_MORA_POST_INC_9M,
    SAFE_DIVIDE(SUM(pf.SDO_MORA_POST_9M), SUM(pf.SDO_TOT_POST_9M)) AS RATIO_POST_INC_90PLUS_9M

FROM UNIVERSO_CATALOGOS c
INNER JOIN PIVOTEO_FINANCIERO pf 
  ON c.CTA_CVE = pf.CTA_CVE
WHERE c.CATALOGO <> 'Segmento Sin Datos' 
GROUP BY 1
ORDER BY 
    CASE c.CATALOGO
      WHEN 'Gen Z'                 THEN 1
      WHEN 'Chava Free Spirit'     THEN 2
      WHEN 'Soltero tecnológico'   THEN 3
      WHEN 'Mamá práctica'        THEN 4
      WHEN 'Jefe de familia'     THEN 5
      WHEN 'Señora generosa'     THEN 6
      WHEN 'Adultos mayores'     THEN 7
      ELSE 8
    END


