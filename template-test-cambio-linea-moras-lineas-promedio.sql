/***********************************************************************************************************************
  PLANTILLA OBJETIVO: ANÁLISIS EVOLUTIVO DE LA LÍNEA DE CRÉDITO PROMEDIO POR COSECHA DE ALTA (HIT VS. NOHIT)
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES (UNIVERSO BASE)
------------------------------------------------------------------------------------------------------------------------
WITH LINEAS AS (
  SELECT
      CTA_CVE,
      BR_HIT_DES
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL > '2025-01-01'
    AND BR_ORG = 210
    AND CTA_CVE > 0
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: HISTÓRICO MENSUAL Y CÁLCULO DE MADURACIÓN (MOB)
------------------------------------------------------------------------------------------------------------------------
VFAC_SDO_CTA_MES AS (
  SELECT 
      a.CTA_CVE,
      a.CTA_IMP_LIM_CRD,
      b.CTA_FCH_ALTA,
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    USING (CTA_CVE)
  WHERE a.TIP_INF = 210
    AND a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND a.ANIO >= 2025
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: DETALLE DE CUENTAS (RECONSTRUCCIÓN DE LÍNEA DE CRÉDITO ASIGNADA)
------------------------------------------------------------------------------------------------------------------------
DETALLE_CUENTAS AS (
  SELECT
      CTA_CVE,
      CTA_FCH_ALTA,
      COALESCE(
        MAX(CASE WHEN MOB <= 1 THEN CTA_IMP_LIM_CRD END), 
        MAX(CTA_IMP_LIM_CRD)
      ) AS CTA_IMP_LIM_CRD
  FROM VFAC_SDO_CTA_MES
  GROUP BY 1, 2
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: REPORTE DE EVOLUCIÓN CRONOLÓGICA DE LÍNEAS PROMEDIO (RENGLÓN GRÁFICA DE TENDENCIA)
------------------------------------------------------------------------------------------------------------------------
SELECT 
    FORMAT_DATE('%Y-%m', d.CTA_FCH_ALTA) AS PERIODO_ALTA, 
    l.BR_HIT_DES,
    AVG(d.CTA_IMP_LIM_CRD) AS LINEA_PROMEDIO      
FROM DETALLE_CUENTAS d
JOIN LINEAS l 
  ON d.CTA_CVE = l.CTA_CVE
WHERE l.BR_HIT_DES IN ('HIT', 'NOHIT')
GROUP BY 1, 2
ORDER BY 1 ASC, l.BR_HIT_DES ASC;
