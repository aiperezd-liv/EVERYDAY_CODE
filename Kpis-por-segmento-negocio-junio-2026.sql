/***********************************************************************************************************************
  SCRIPT DE PORTAFOLIO CORREGIDO: ANÁLISIS POR CATÁLOGOS (EDAD Y GÉNERO) - MÉTRICAS POR SALDO
  MÉTRICAS: Aprobación, Línea Promedio, Activación y Maduración de Moras por Saldo (Entry@2MoB, 30+@3MoB, 90+@9MoB)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES ENTRANTES (UNIVERSO BASE SIN FILTROS DE PRODUCTO)
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES AS (
  SELECT
      BR_SOLIC_CVE,
      BR_TIPO,
      CTA_CVE,
      BR_HIT_DES,
      DT_FCH_SOL,
      BR_STATUS
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2025-01-01' AND '2025-08-31'
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: DATOS DEMOGRÁFICOS BASE (CORRECCIÓN CRÍTICA DE MAPEO DE GÉNERO M=MASCULINO)
------------------------------------------------------------------------------------------------------------------------
DEMOGRAFICOS AS (
  SELECT * FROM (
    SELECT 
        BR_SOLIC_CVE,
        BR_TIPO,
        BR_EDAD,
        -- Mapeo estricto basado en las reglas reales de la base de datos
        CASE 
          WHEN TRIM(UPPER(BR_SEXO)) IN ('FEMENINO', 'F')   THEN 'M' -- 'M' de segmentación interna (Mujer)
          WHEN TRIM(UPPER(BR_SEXO)) IN ('MASCULINO', 'M')  THEN 'H' -- 'H' de segmentación interna (Hombre)
          ELSE 'DESCONOCIDO'
        END AS BR_GENERO
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_APIA`
  )
  -- Solo filtramos los géneros bien homologados
  WHERE BR_GENERO IN ('M', 'H')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: MATRIZ DE CATÁLOGOS Y REGLA DE APROBACIÓN SIMPLIFICADA
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CATALOGOS AS (
  SELECT 
      s.*,
      COALESCE(d.BR_EDAD, 0) AS BR_EDAD,
      d.BR_GENERO,
      
      -- Regla de Aprobación estricta (Solo primera condición activa)
      IF(s.BR_STATUS IN ('A','T','E') AND s.CTA_CVE > 0, 1, 0) AS IND_APROBADO,

      -- Clasificación por Ciclo de Vida / Catálogos basados en Edad y Género homologados
      CASE 
        WHEN d.BR_EDAD BETWEEN 18 AND 24                       THEN 'Gen Z'
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
    AND s.BR_TIPO = d.BR_TIPO
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: COMPORTAMIENTO MENSUAL Y ACTIVACIÓN HISTÓRICA
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_NIV_MOR,
      a.CTA_SDO_ACT,
      a.CTA_IMP_LIM_CRD,
      b.CTA_FCH_ALTA,
      -- Ventana fija de activación a 3 meses utilizando valor absoluto
      MAX(CASE 
        WHEN a.CTA_FCH_PRM_CMP IS NOT NULL 
         AND ABS(DATE_DIFF(DATE(a.CTA_FCH_PRM_CMP), DATE(b.CTA_FCH_ALTA), MONTH)) <= 3 THEN 1 
        ELSE 0 
      END) OVER(PARTITION BY a.CTA_CVE) AS IND_ACTIVACION_3M,
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b 
    USING (CTA_CVE)
  WHERE a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: PIVOTEO FINANCIERO Y COMPORTAMIENTO DE MORAS POR SALDO
------------------------------------------------------------------------------------------------------------------------
COMPORTAMIENTO_CUENTAS AS (
  SELECT
      CTA_CVE,
      MAX(IND_ACTIVACION_3M) AS IND_ACTIVACION,
      COALESCE(
        MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
        MAX(CTA_IMP_LIM_CRD)
      ) AS LINEA_CREDITO,

      -- EVALUACIÓN MOB 2 (Mora Temprana Entry: Niv Mora >= 2)
      MAX(CASE WHEN MOB = 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_2M,
      MAX(CASE WHEN MOB = 2 AND CTA_NIV_MOR >= 2 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_2M,

      -- EVALUACIÓN MOB 3 (Mora Mínima 30+: Niv Mora >= 3)
      MAX(CASE WHEN MOB = 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_3M,
      MAX(CASE WHEN MOB = 3 AND CTA_NIV_MOR >= 3 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_3M,

      -- EVALUACIÓN MOB 9 (Mora Avanzada 90+: Niv Mora >= 5)
      MAX(CASE WHEN MOB = 9 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_TOT_9M,
      MAX(CASE WHEN MOB = 9 AND CTA_NIV_MOR >= 5 THEN GREATEST(CTA_SDO_ACT, 0) ELSE 0 END) AS SDO_MORA_9M
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: AGREGACIÓN DE RATIOS OPERATIVOS Y DE EXPOSICIÓN EN RIESGO POR GRUPO OBJETIVO
------------------------------------------------------------------------------------------------------------------------
SELECT
    c.CATALOGO,
    COUNT(*) AS TOTAL_SOLICITUDES,
    SUM(c.IND_APROBADO) AS TOTAL_APROBADAS,
    SAFE_DIVIDE(SUM(c.IND_APROBADO), COUNT(*)) AS TASA_APROBACION,
    COUNT(CASE WHEN c.CTA_CVE > 0 THEN 1 END) AS TOTAL_CUENTAS,
    ROUND(AVG(CASE WHEN c.CTA_CVE > 0 THEN cc.LINEA_CREDITO END), 2) AS LINEA_PROMEDIO,
    
    SAFE_DIVIDE(SUM(CASE WHEN c.CTA_CVE > 0 THEN cc.IND_ACTIVACION ELSE 0 END), 
                COUNT(CASE WHEN c.CTA_CVE > 0 THEN 1 END)) AS TASA_ACTIVACION_3M,

    -- Indicadores de Maduración de Pérdidas Calculados con Saldos Reales del Corte de cada MoB
    SAFE_DIVIDE(SUM(cc.SDO_MORA_2M), SUM(cc.SDO_TOT_2M)) AS RATIO_ENTRY_AT_2MOB_SDO,
    SAFE_DIVIDE(SUM(cc.SDO_MORA_3M), SUM(cc.SDO_TOT_3M)) AS RATIO_30_PLUS_AT_3MOB_SDO,
    SAFE_DIVIDE(SUM(cc.SDO_MORA_9M), SUM(cc.SDO_TOT_9M)) AS RATIO_90_PLUS_AT_9MOB_SDO

FROM UNIVERSO_CATALOGOS c
LEFT JOIN COMPORTAMIENTO_CUENTAS cc 
  ON c.CTA_CVE = cc.CTA_CVE
WHERE c.CATALOGO NOT IN ('Segmento Sin Datos', 'No Clasificado')
GROUP BY 1
ORDER BY 
    CASE c.CATALOGO
      WHEN 'Gen Z'               THEN 1
      WHEN 'Chava Free Spirit'   THEN 2
      WHEN 'Soltero tecnológico' THEN 3
      WHEN 'Mamá práctica'       THEN 4
      WHEN 'Jefe de familia'     THEN 5
      WHEN 'Señora generosa'     THEN 6
      WHEN 'Adultos mayores'     THEN 7
      ELSE 8
    END;
