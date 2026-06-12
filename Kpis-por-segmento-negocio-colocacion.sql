/***********************************************************************************************************************
  SCRIPT DE PORTAFOLIO 2026: COLOCACIÓN, ACTIVACIÓN, UTILIZACIÓN Y TICKET PROMEDIO HISTÓRICO GENERAL
  MÉTRICAS: Solicitudes, Aprobadas, % Aprobación, Línea Promedio, Tasa de Activación 3M, % Utilización y Ticket Promedio
  FILTRO: Cosecha Nueva >= 2026-01-01 con Filtro Final por BR_ORG y Métricas de Uso Generalizadas (Sin Tope de MOB)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES ENTRANTES COSECHA 2026
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES AS (
  SELECT
      BR_SOLIC_CVE,
      BR_ORG, -- Variable arrastrada para el filtrado final
      CTA_CVE,
      BR_STATUS
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL >= '2026-01-01'
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
          WHEN TRIM(UPPER(BR_SEXO)) IN ('FEMENINO', 'F')   THEN 'M' 
          WHEN TRIM(UPPER(BR_SEXO)) IN ('MASCULINO', 'M')  THEN 'H' 
          ELSE 'DESCONOCIDO'
        END AS BR_GENERO
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_APIA`
  )
  WHERE BR_GENERO IN ('M', 'H')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: MATRIZ DE CATÁLOGOS Y REGLA DE APROBACIÓN ESTRICTA
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CATALOGOS AS (
  SELECT 
      s.*,
      COALESCE(d.BR_EDAD, 0) AS BR_EDAD,
      d.BR_GENERO,
      
      -- Regla de Aprobación estricta
      IF(s.BR_STATUS IN ('A','T','E') AND s.CTA_CVE > 0, 1, 0) AS IND_APROBADO,

      -- Clasificación por Ciclo de Vida / Catálogos homologados
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
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: COMPORTAMIENTO MENSUAL COSECHA 2026 (ACTIVACIÓN, USO Y TRANSACCIONALIDAD GENERAL)
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_SDO_ACT,
      a.CTA_IMP_LIM_CRD,
      a.CTA_IMP_CMP_YTD,
      a.CTA_NUM_CMP_YTD,
      b.CTA_FCH_ALTA,
      -- Ventana fija de activación a 3 meses utilizando valor absoluto
      MAX(CASE 
        WHEN a.CTA_FCH_PRM_CMP IS NOT NULL 
         AND ABS(DATE_DIFF(DATE(a.CTA_FCH_PRM_CMP), DATE(b.CTA_FCH_ALTA), MONTH)) <= 3 THEN 1 
        ELSE 0 
      END) OVER(PARTITION BY a.CTA_CVE) AS IND_ACTIVACION_3M,
      
      -- Porcentaje de utilización por mes
      SAFE_DIVIDE(GREATEST(a.CTA_SDO_ACT, 0), a.CTA_IMP_LIM_CRD) AS PCT_UTILIZACION_MES,
      -- Ticket promedio transaccional del periodo del corte
      SAFE_DIVIDE(a.CTA_IMP_CMP_YTD, a.CTA_NUM_CMP_YTD) AS TICKET_PROMEDIO_MES,
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b 
    USING (CTA_CVE)
  WHERE a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND b.CTA_FCH_ALTA >= '2026-01-01' -- Cuentas 2026
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: PIVOTEO OPERATIVO HISTÓRICO GENERAL POR CUENTA
------------------------------------------------------------------------------------------------------------------------
COMPORTAMIENTO_CUENTAS AS (
  SELECT
      CTA_CVE,
      MAX(IND_ACTIVACION_3M) AS IND_ACTIVACION,
      COALESCE(
        MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
        MAX(CTA_IMP_LIM_CRD)
      ) AS LINEA_CREDITO,
      -- Se remueve el tope "BETWEEN 0 AND 3"; se evalúa el comportamiento histórico general (MOB >= 0)
      MAX(CASE WHEN MOB >= 0 THEN PCT_UTILIZACION_MES ELSE 0 END) AS MAX_UTILIZACION,
      MAX(CASE WHEN MOB >= 0 THEN TICKET_PROMEDIO_MES ELSE 0 END) AS TICKET_PROMEDIO_CTA
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: METRICAS COMERCIALES Y DE TRANSACCIONALIDAD COMPLETAS GENERALES
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
                
    ROUND(AVG(CASE WHEN c.CTA_CVE > 0 THEN cc.MAX_UTILIZACION END), 4) AS TASA_UTILIZACION_PROM,
    ROUND(AVG(CASE WHEN c.CTA_CVE > 0 AND cc.TICKET_PROMEDIO_CTA > 0 THEN cc.TICKET_PROMEDIO_CTA END), 2) AS TICKET_PROMEDIO_PROM

FROM UNIVERSO_CATALOGOS c
LEFT JOIN COMPORTAMIENTO_CUENTAS cc 
  ON c.CTA_CVE = cc.CTA_CVE
WHERE c.CATALOGO <> 'Segmento Sin Datos'
  -- ===================================================================================================================
  -- FILTRADO ÚNICO AL FINAL POR LA VARIABLE ARRASTRADA
  -- ===================================================================================================================
  AND c.BR_ORG = 200
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
