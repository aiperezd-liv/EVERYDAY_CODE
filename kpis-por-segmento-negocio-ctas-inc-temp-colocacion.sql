/***********************************************************************************************************************
  SCRIPT DE PORTAFOLIO: COLOCACIÓN, ACTIVACIÓN, UTILIZACIÓN, COMPRAS, GASTO Y SALDOS PRE VS POST INCREMENTO
  MÉTRICAS: Solicitudes, % Activación, Líneas, Utilización, Ticket, Compras, Gasto Mensual y Saldo Promedio.
  FILTRO: Solicitudes entre ENE 25 y JUN 25 / Cuentas con Alta >= 2025-01-01 e Incremento entre MOB 9 y 12 / BR_ORG = 200
***********************************************************************************************************************/

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 1: SOLICITUDES ENTRANTES COSECHA ENERO 2025 - JUNIO 2025
------------------------------------------------------------------------------------------------------------------------
WITH SOLICITUDES AS (
  SELECT
      BR_SOLIC_CVE,
      CTA_CVE,
      BR_STATUS
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES`
  WHERE DT_FCH_SOL BETWEEN '2025-01-01' AND '2025-06-30'
    AND BR_ORG = 200
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 2: DATOS DEMOGRÁFICOS BASE
------------------------------------------------------------------------------------------------------------------------
DEMOGRAFICOS AS (
  SELECT BR_SOLIC_CVE, BR_EDAD, BR_GENERO
  FROM (
    SELECT
        BR_SOLIC_CVE,
        BR_EDAD,
        CASE
          WHEN TRIM(UPPER(BR_SEXO)) IN ('FEMENINO', 'F')   THEN 'M'   -- Mujer
          WHEN TRIM(UPPER(BR_SEXO)) IN ('MASCULINO', 'M') THEN 'H'   -- Hombre
          ELSE 'DESCONOCIDO'
        END AS BR_GENERO
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_APIA`
  )
  WHERE BR_GENERO IN ('M', 'H')
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 3: MATRIZ DE CATÁLOGOS Y REGLA DE APROBACIÓN
------------------------------------------------------------------------------------------------------------------------
UNIVERSO_CATALOGOS AS (
  SELECT * FROM (
    SELECT
        s.BR_SOLIC_CVE,
        s.CTA_CVE,
        IF(s.BR_STATUS IN ('A','T','E') AND s.CTA_CVE > 0, 1, 0) AS IND_APROBADO,
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
    LEFT JOIN DEMOGRAFICOS d ON s.BR_SOLIC_CVE = d.BR_SOLIC_CVE
  )
  WHERE CATALOGO <> 'Segmento Sin Datos'
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 4: BASE ÚNICA DE MOVIMIENTOS MENSUALES (SIN TOPE DE MOB)
------------------------------------------------------------------------------------------------------------------------
MOVIMIENTOS_CTA AS (
  SELECT
      a.CTA_CVE,
      a.CTA_SDO_ACT,       -- Variable agregada para cálculo de saldos promedio
      a.CTA_IMP_LIM_CRD,
      a.CTA_LAST_LIM_CRE,
      a.CTA_IMP_MCMP_LTD,
      a.CTA_NUM_CMP_LTD,
      a.CTA_FCH_PRM_CMP,
      b.CTA_FCH_ALTA,
      DATE_DIFF(DATE(a.ANIO, a.MES, 1), DATE_TRUNC(b.CTA_FCH_ALTA, MONTH), MONTH) AS MOB,
      SAFE_DIVIDE(GREATEST(a.CTA_SDO_ACT, 0), a.CTA_IMP_LIM_CRD) AS PCT_UTILIZACION_MES
  FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VFAC_SDO_CTA_MES` a
  LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA` b
    ON a.CTA_CVE = b.CTA_CVE
  WHERE a.CTA_EDO_CVE NOT IN ('T', 'P', 'Z', '8', '9')
    AND b.CTA_FCH_ALTA >= '2025-01-01'
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 5: CUENTAS TARGET (ACTIVACIÓN 3M + DETECCIÓN DE INCREMENTO ENTRE MOB 9 Y 12)
------------------------------------------------------------------------------------------------------------------------
CUENTAS_TARGET AS (
  SELECT
      CTA_CVE,
      MAX(CASE
            WHEN MOB BETWEEN 0 AND 12
             AND CTA_FCH_PRM_CMP IS NOT NULL
             AND ABS(DATE_DIFF(DATE(CTA_FCH_PRM_CMP), DATE_TRUNC(CTA_FCH_ALTA, MONTH), MONTH)) <= 3
            THEN 1 ELSE 0
          END) AS IND_ACTIVACION_3M,
      MAX(CASE
            WHEN MOB BETWEEN 0 AND 12
             AND CTA_LAST_LIM_CRE > 0 AND CTA_IMP_LIM_CRD > CTA_LAST_LIM_CRE
            THEN 1 ELSE 0
          END) AS INC_TEMP,
      MAX(CASE
            WHEN MOB BETWEEN 0 AND 12
             AND CTA_LAST_LIM_CRE > 0 AND CTA_IMP_LIM_CRD > CTA_LAST_LIM_CRE
            THEN MOB
          END) AS MOB_INC
  FROM MOVIMIENTOS_CTA
  GROUP BY 1
  HAVING MOB_INC BETWEEN 9 AND 12
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 6: HISTORIAL COMPLETO SOLO PARA CUENTAS TARGET
------------------------------------------------------------------------------------------------------------------------
COMPORTAMIENTO_HISTORICO AS (
  SELECT
      m.CTA_CVE,
      m.CTA_SDO_ACT,
      m.CTA_IMP_LIM_CRD,
      m.CTA_IMP_MCMP_LTD,
      m.CTA_NUM_CMP_LTD,
      m.PCT_UTILIZACION_MES,
      m.MOB,
      t.IND_ACTIVACION_3M AS ETIQUETA_ACTIVACION,
      t.INC_TEMP          AS ETIQUETA_INC_TEMP,
      t.MOB_INC           AS ETIQUETA_MOB_INC
  FROM MOVIMIENTOS_CTA m
  INNER JOIN CUENTAS_TARGET t ON m.CTA_CVE = t.CTA_CVE
),

------------------------------------------------------------------------------------------------------------------------
-- MÓDULO 7: PIVOTEO PRE / POST CON VENTANAS SIMÉTRICAS ACOTADAS EN LTD
------------------------------------------------------------------------------------------------------------------------
COMPORTAMIENTO_CUENTAS AS (
  SELECT
      CTA_CVE,
      MAX(ETIQUETA_ACTIVACION) AS IND_ACTIVACION,
      MAX(ETIQUETA_INC_TEMP)   AS INC_TEMP,
      MAX(ETIQUETA_MOB_INC)    AS MOB_INC,

      -- =======================================================================
      -- INDICADORES ETAPA PRE-INCREMENTO
      -- =======================================================================
      AVG(CASE WHEN MOB < ETIQUETA_MOB_INC THEN CTA_IMP_LIM_CRD END) AS LINEA_CREDITO_PRE,
      MAX(CASE WHEN MOB < ETIQUETA_MOB_INC THEN PCT_UTILIZACION_MES ELSE 0 END) AS MAX_UTILIZACION_PRE,
      AVG(CASE WHEN MOB < ETIQUETA_MOB_INC THEN GREATEST(CTA_SDO_ACT, 0) END) AS SALDO_PROMEDIO_PRE, -- Saldo Promedio PRE
      
      -- Snapshots congelados un mes antes del incremento (LTD)
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_NUM_CMP_LTD END) AS ACUM_COMPRAS_PRE,
      MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_IMP_MCMP_LTD END) AS ACUM_GASTO_PRE,
      SAFE_DIVIDE(
        MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_IMP_MCMP_LTD END),
        MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_NUM_CMP_LTD END)
      ) AS TICKET_PROMEDIO_PRE,

      -- =======================================================================
      -- INDICADORES ETAPA POST-INCREMENTO ACOTADA (VENTANA SIMÉTRICA)
      -- =======================================================================
      AVG(CASE WHEN MOB >= ETIQUETA_MOB_INC AND MOB < (2 * ETIQUETA_MOB_INC) THEN CTA_IMP_LIM_CRD END) AS LINEA_CREDITO_POST,
      MAX(CASE WHEN MOB >= ETIQUETA_MOB_INC AND MOB < (2 * ETIQUETA_MOB_INC) THEN PCT_UTILIZACION_MES ELSE 0 END) AS MAX_UTILIZACION_POST,
      AVG(CASE WHEN MOB >= ETIQUETA_MOB_INC AND MOB < (2 * ETIQUETA_MOB_INC) THEN GREATEST(CTA_SDO_ACT, 0) END) AS SALDO_PROMEDIO_POST, -- Saldo Promedio POST
      
      -- Compras Netas POST (Techo simétrico menos corte PRE)
      (MAX(CASE WHEN MOB < (2 * ETIQUETA_MOB_INC) THEN CTA_NUM_CMP_LTD END) 
       - COALESCE(MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_NUM_CMP_LTD END), 0)) AS ACUM_COMPRAS_POST,
      
      -- Gasto Neto POST (Techo simétrico menos corte PRE)
      (MAX(CASE WHEN MOB < (2 * ETIQUETA_MOB_INC) THEN CTA_IMP_MCMP_LTD END) 
       - COALESCE(MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_IMP_MCMP_LTD END), 0)) AS ACUM_GASTO_POST,
      
      -- Ticket Promedio POST
      SAFE_DIVIDE(
        (MAX(CASE WHEN MOB < (2 * ETIQUETA_MOB_INC) THEN CTA_IMP_MCMP_LTD END) - COALESCE(MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_IMP_MCMP_LTD END), 0)),
        (MAX(CASE WHEN MOB < (2 * ETIQUETA_MOB_INC) THEN CTA_NUM_CMP_LTD END) - COALESCE(MAX(CASE WHEN MOB = (ETIQUETA_MOB_INC - 1) THEN CTA_NUM_CMP_LTD END), 0))
      ) AS TICKET_PROMEDIO_POST,

      -- Conteos de meses observados para mensualizar de forma exacta
      COUNT(CASE WHEN MOB < ETIQUETA_MOB_INC THEN 1 END) AS MESES_ETAPA_PRE,
      COUNT(CASE WHEN MOB >= ETIQUETA_MOB_INC AND MOB < (2 * ETIQUETA_MOB_INC) THEN 1 END) AS MESES_ETAPA_POST

  FROM COMPORTAMIENTO_HISTORICO
  GROUP BY 1
)

------------------------------------------------------------------------------------------------------------------------
-- OUTPUT FINAL
------------------------------------------------------------------------------------------------------------------------
SELECT
    c.CATALOGO,
    COUNT(*) AS TOTAL_SOLICITUDES,   
    SAFE_DIVIDE(SUM(cc.IND_ACTIVACION), COUNT(*)) AS TASA_ACTIVACION_3M,

    -- =========================================================================
    -- BLOQUE A: PERFORMANCE ETAPA PRE-INCREMENTO
    -- =========================================================================
    ROUND(AVG(cc.LINEA_CREDITO_PRE), 2)   AS LINEA_PROMEDIO_PRE,
    ROUND(AVG(cc.MAX_UTILIZACION_PRE), 4) AS TASA_UTILIZACION_PROM_PRE,
    ROUND(AVG(cc.SALDO_PROMEDIO_PRE), 2)  AS SALDO_PROMEDIO_PROM_PRE,
    ROUND(AVG(CASE WHEN cc.TICKET_PROMEDIO_PRE > 0 THEN cc.TICKET_PROMEDIO_PRE END), 2) AS TICKET_PROMEDIO_PROM_PRE,
    ROUND(AVG(SAFE_DIVIDE(cc.ACUM_COMPRAS_PRE, cc.MESES_ETAPA_PRE)), 2) AS COMPRAS_PROMEDIO_MES_PRE,
    ROUND(AVG(SAFE_DIVIDE(cc.ACUM_GASTO_PRE, cc.MESES_ETAPA_PRE)), 2) AS GASTO_PROMEDIO_MES_PRE,

    -- =========================================================================
    -- BLOQUE B: PERFORMANCE ETAPA POST-INCREMENTO (VENTANA SIMÉTRICA ACOTADA)
    -- =========================================================================
    ROUND(AVG(cc.LINEA_CREDITO_POST), 2)   AS LINEA_PROMEDIO_POST,
    ROUND(AVG(cc.MAX_UTILIZACION_POST), 4) AS TASA_UTILIZACION_PROM_POST,
    ROUND(AVG(cc.SALDO_PROMEDIO_POST), 2)  AS SALDO_PROMEDIO_PROM_POST,
    ROUND(AVG(CASE WHEN cc.TICKET_PROMEDIO_POST > 0 THEN cc.TICKET_PROMEDIO_POST END), 2) AS TICKET_PROMEDIO_PROM_POST,
    ROUND(AVG(SAFE_DIVIDE(cc.ACUM_COMPRAS_POST, cc.MESES_ETAPA_POST)), 2) AS COMPRAS_PROMEDIO_MES_POST,
    ROUND(AVG(SAFE_DIVIDE(cc.ACUM_GASTO_POST, cc.MESES_ETAPA_POST)), 2) AS GASTO_PROMEDIO_MES_POST

FROM UNIVERSO_CATALOGOS c
INNER JOIN COMPORTAMIENTO_CUENTAS cc ON c.CTA_CVE = cc.CTA_CVE
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
