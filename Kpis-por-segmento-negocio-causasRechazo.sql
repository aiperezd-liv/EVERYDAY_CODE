/***********************************************************************************************************************
  SCRIPT DE PORTAFOLIO 2026: ANÁLISIS DE CAUSAS DE RECHAZO POR CATÁLOGOS (1ER SEMESTRE 2026)
  MÉTRICAS: Volumen de Rechazos y % de Participación por Causa de Rechazo Principal por Segmento
  FILTRO: DT_FCH_SOL entre '2026-01-01' y '2026-06-30' con Filtro Final por BR_ORG
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES RECHAZADAS EN EL 1ER SEMESTRE 2026
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES_RECHAZADAS AS (
  SELECT
      BR_SOLIC_CVE,
      BR_ORG, -- Variable arrastrada para el filtrado final
      CTA_CVE,
      BR_STATUS,
      CAUSA_RECHAZO -- Solo nos quedamos con la causa principal
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2026-01-01' AND '2026-06-30' -- Acotado al primer semestre de 2026
    -- Filtro estricto para asegurar que solo analizamos el universo de rechazos
    AND NOT (BR_STATUS IN ('A','T','E') AND CTA_CVE > 0)
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
-- MÓDULO 3: MATRIZ DE CATÁLOGOS ASOCIADA A RECHAZOS
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CATALOGOS AS (
  SELECT 
      s.*, -- Mantiene s.BR_ORG y s.CAUSA_RECHAZO
      COALESCE(d.BR_EDAD, 0) AS BR_EDAD,
      d.BR_GENERO,

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
  FROM SOLICITUDES_RECHAZADAS s
  LEFT JOIN DEMOGRAFICOS d 
     ON s.BR_SOLIC_CVE = d.BR_SOLIC_CVE
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL: AGREGACIÓN EXCLUSIVA POR CAUSA DE RECHAZO CON DISTRIBUCIÓN PORCENTUAL
------------------------------------------------------------------------------------------------------------------------
SELECT
    c.CATALOGO,
    COALESCE(c.CAUSA_RECHAZO, 'SIN ESPECIFICAR') AS CAUSA_RECHAZO, -- Nivel único de agregación
    COUNT(*) AS VOLUMEN_RECHAZOS,
    
    -- Calcula el % que representa esta causa específica sobre el total de rechazos de este catálogo
    ROUND(
      SAFE_DIVIDE(
        COUNT(*), 
        SUM(COUNT(*)) OVER(PARTITION BY c.CATALOGO)
      ), 4
    ) AS PCT_PARTICIPACION_RECHAZO

FROM UNIVERSO_CATALOGOS c
WHERE c.CATALOGO <> 'Segmento Sin Datos'
  -- ===================================================================================================================
  -- FILTRADO ÚNICO AL FINAL POR LA VARIABLE ARRASTRADA
  -- ===================================================================================================================
  AND c.BR_ORG = 200 
  -- and CATALOGO = 'Mamá práctica'
GROUP BY 1, 2
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
    END,
    VOLUMEN_RECHAZOS DESC;
