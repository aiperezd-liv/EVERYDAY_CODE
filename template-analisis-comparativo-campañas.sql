/**
 * =================================================================================
 * TEMPLATE BASE: COMPARATIVA DE MÉTRICAS ENTRE SUBMUESTRAS (UNIVERSO CRÉDITO)
 * =================================================================================
 */

-- ==========================================
-- 0. CONFIGURACIÓN DE PARÁMETROS Y VARIABLES
-- ==========================================
DECLARE FCH_HOY DATE DEFAULT CURRENT_DATE('America/Mexico_City');
DECLARE FCH_INI DATE DEFAULT ('2026-01-01');                             -- <--- Fecha de inicio del piloto 
DECLARE FCH_FIN DATE DEFAULT (LAST_DAY(DATE_TRUNC(FCH_HOY, YEAR), YEAR));

WITH 
-- ==========================================
-- 1. MÓDULO: HISTÓRICO DE FLUJOS (PEGA)
-- ==========================================

VFAC_OMDM_FLUJO AS (
  SELECT 
    BR_SOLIC_CVE,
    BR_TIPO,
    MIN(BR_ORG) AS PROD_SOLICITADO,
    MAX(BR_ORG) AS PROD_OFERTADO,
    MAX(IF(FLAG_QUASH='TRUE' AND BR_FLUJO_CVE = 6 AND BR_ORG = 210, 1, 0)) AS FLAG_QUASH,
    MAX(BR_TASA_CVE) AS TASA,
    MAX(BR_IMP_LIM_CRED_APROB) AS BR_IMP_LIM_CRED
  FROM `MUS_PRO_DWH_SAS_TEMP.DWH_FAC_OMDM_FLUJO_APM_PEGA`                 -- <--- Cambiar por tabla productiva correspondiente
  WHERE FCH_CARGA >= FCH_INI
    AND BR_ORG IN (200, 210, 230)
  GROUP BY 1, 2
),

-- ==========================================
-- 2. MÓDULO: ESTADOS DE CONTROL (APIS)
-- ==========================================
-- Deduplica las solicitudes seleccionando el último estado prioritario por jerarquía de negocio.
APIS AS (
  SELECT 
    BR_SOLIC_CVE,
    BR_TIPO,
    BR_STATUS,
    BR_LIM_CRD
  FROM (
    SELECT 
      BR_SOLIC_CVE,
      BR_TIPO,
      BR_STATUS,
      BR_DOWNSELL,
      BR_LIM_CRD,
      ROW_NUMBER() OVER (
        PARTITION BY BR_SOLIC_CVE, BR_TIPO
        ORDER BY 
          CASE BR_STATUS
            WHEN 'T' THEN 5
            WHEN 'D' THEN 4
            WHEN 'A' THEN 3
            WHEN 'C' THEN 2
            ELSE 0
          END DESC
      ) AS rn
    FROM `MUS_PRO_DWH_SAS_TEMP.DWH_FAC_APIS_APM_PEGA`                    
    WHERE BR_ORG IN (200, 210, 230)
      AND FCH_CARGA >= FCH_INI
  )
  WHERE rn = 1
),

-- ==========================================
-- 3. MÓDULO: UNIVERSO CONSOLIDADO (SOLICITUDES)
-- ==========================================

SOLICITUDES AS (
  SELECT
    a.BR_SOLIC_CVE,
    a.BR_TIPO,
    a.BR_ORG,
    a.SegmentoScore,
    a.BR_FCH_SOLIC,
    a.BR_SCORE_FIN,
    a.BR_HIT_CVE,
    a.TDA_CVE,
    b.TASA,
    b.BR_IMP_LIM_CRED,
    c.CTA_CVE,
    c.CTA_FCH_ALTA,
    d.BR_EDAD,
    d.BR_SEXO,
    d.BR_EDC_CVE,
    d.BR_ESCOLARIDAD,
    d.BR_ING_TOT,
    d.BR_TIP_VDA,
    d.BR_GIRO,
    d.ESTATUS_SOLICITUD_APLICACION,
    f.BR_STATUS,
    
    -- Métricas Derivadas / Ratios de Capacidad
    b.BR_IMP_LIM_CRED / GREATEST(d.BR_ING_TOT, 2000) AS LTI_ONUS,
    
    -- [--- ESPACIO COMENTADO: AGREGAR NUEVAS COLUMNAS O RATIOS DE BURO/CAPACIDAD AQUÍ ---]
    -- e.PTI,
    -- e.BTI,
    -- e.IQ_NUM_CONS_3M,

    -- Lógica de negocio: Segmentación de Canales, Productos y Flujos
    CASE
      WHEN b.PROD_SOLICITADO <> b.PROD_OFERTADO THEN 'Downsell'
      WHEN b.FLAG_QUASH = 1 THEN 'QUASH'
      ELSE 'BAU'
    END AS Flujo,
    
    CASE
      WHEN a.BR_ORG = 210 THEN 'Departamental'
      WHEN a.BR_ORG = 230 THEN 'Minipagos'
      WHEN a.BR_ORG = 200 THEN 'VISA' 
    END AS Producto,

    -- Filtros de Campaña / Eventos Cronológicos (Configurable por piloto)
    CASE
      WHEN a.BR_FCH_SOLIC BETWEEN '2026-03-23' AND '2026-03-26' AND a.TDA_CVE IN ('0597','0551') AND a.SYS_FTE = 148 THEN 'Friends & Family Tienda'
      WHEN a.BR_FCH_SOLIC >= '2026-03-27'                      AND a.TDA_CVE IN ('0597','0551') AND a.SYS_FTE = 148 THEN 'GO-LIVE Tienda'
      WHEN a.BR_FCH_SOLIC BETWEEN '2026-05-11' AND '2026-05-19' AND a.TDA_CVE = '0782'           AND a.SYS_FTE = 148 THEN 'Friends & Family Online'
      WHEN a.BR_FCH_SOLIC >= '2026-05-20'                      AND a.TDA_CVE = '0782'           AND a.SYS_FTE = 148 THEN 'GO-LIVE Online'
      ELSE 'BAU'
    END AS Venta,
    -- Filtros de Tienda (Configurable por piloto)
    CASE 
      WHEN a.TDA_CVE = '0782' THEN 'Online'
      WHEN a.TDA_CVE = '0551' THEN 'Cuajimalpa'
      WHEN a.TDA_CVE = '0597' THEN 'CD Jardín'
    END AS Tienda,

    CASE
      WHEN a.BR_TIPO IN (1001,1011,1021,1031) THEN 'X-Sell'
      WHEN a.BR_ORG = 200 AND a.BR_HIT_CVE = 1 AND a.SegmentoScore IN (10,16,33,34,35) THEN 'Doble'
      WHEN a.BR_ORG = 200 AND a.BR_HIT_CVE = 1 THEN 'Puro'
      WHEN a.BR_HIT_CVE = 1 THEN 'Hit'
      WHEN a.BR_HIT_CVE = 2 THEN 'No Hit'
      WHEN a.BR_HIT_CVE = 0 THEN 'Thin File'
      ELSE 'Sin Hit'
    END AS Segmento,
    
    CASE
      WHEN a.BR_TIPO IN (102,1020,1021) THEN 'Empleado' ELSE 'Cliente' 
    END AS ClienteEmpleado,
    
    CASE 
      WHEN a.TDA_CVE = '0782' THEN 'Online' 
      ELSE 'Tienda'
    END AS Canal,

    -- Matriz de Riesgo Paramétrica basada en Score y Segmento
    CASE
      -- 13 SBBVISAPURO2021
      WHEN a.SegmentoScore=13 AND BR_SCORE_FIN <= 230 THEN 5
      WHEN a.SegmentoScore=13 AND BR_SCORE_FIN <= 248 THEN 4
      WHEN a.SegmentoScore=13 AND BR_SCORE_FIN <= 255 THEN 3
      WHEN a.SegmentoScore=13 AND BR_SCORE_FIN <= 271 THEN 2
      WHEN a.SegmentoScore=13 AND BR_SCORE_FIN > 271  THEN 1
      -- 16 SBBVISADOBLES2021
      WHEN a.SegmentoScore=16 AND BR_SCORE_FIN <= 245 THEN 5
      WHEN a.SegmentoScore=16 AND BR_SCORE_FIN <= 254 THEN 4
      WHEN a.SegmentoScore=16 AND BR_SCORE_FIN <= 261 THEN 3
      WHEN a.SegmentoScore=16 AND BR_SCORE_FIN <= 268 THEN 2
      WHEN a.SegmentoScore=16 AND BR_SCORE_FIN > 268  THEN 1
      -- 18 CLSDREVTL
      WHEN a.SegmentoScore=18 AND BR_SCORE_FIN < 237  THEN 5
      WHEN a.SegmentoScore=18 AND BR_SCORE_FIN < 249  THEN 4
      WHEN a.SegmentoScore=18 AND BR_SCORE_FIN < 264  THEN 3
      WHEN a.SegmentoScore=18 AND BR_SCORE_FIN < 274  THEN 2
      WHEN a.SegmentoScore=18 AND BR_SCORE_FIN >= 274 THEN 1
      -- 19 SINNREVTL_AGEGE30
      WHEN a.SegmentoScore=19 AND BR_SCORE_FIN < 243  THEN 5
      WHEN a.SegmentoScore=19 AND BR_SCORE_FIN < 250  THEN 4
      WHEN a.SegmentoScore=19 AND BR_SCORE_FIN < 255  THEN 3
      WHEN a.SegmentoScore=19 AND BR_SCORE_FIN < 264  THEN 2
      WHEN a.SegmentoScore=19 AND BR_SCORE_FIN >= 264 THEN 1
      -- 20 SINNREVTL_AGELT30
      WHEN a.SegmentoScore=20 AND BR_SCORE_FIN < 237  THEN 5
      WHEN a.SegmentoScore=20 AND BR_SCORE_FIN < 247  THEN 4
      WHEN a.SegmentoScore=20 AND BR_SCORE_FIN < 252  THEN 3
      WHEN a.SegmentoScore=20 AND BR_SCORE_FIN >= 252 THEN 2
      -- 21 NEWTOREVOLVING
      WHEN a.SegmentoScore=21 AND BR_SCORE_FIN < 234  THEN 5
      WHEN a.SegmentoScore=21 AND BR_SCORE_FIN < 249  THEN 4
      WHEN a.SegmentoScore=21 AND BR_SCORE_FIN < 264  THEN 3
      WHEN a.SegmentoScore=21 AND BR_SCORE_FIN < 274  THEN 2
      WHEN a.SegmentoScore=21 AND BR_SCORE_FIN >= 274 THEN 1
      -- 22 THICKREV
      WHEN a.SegmentoScore=22 AND BR_SCORE_FIN < 230  THEN 5
      WHEN a.SegmentoScore=22 AND BR_SCORE_FIN < 236  THEN 4
      WHEN a.SegmentoScore=22 AND BR_SCORE_FIN < 246  THEN 3
      WHEN a.SegmentoScore=22 AND BR_SCORE_FIN < 256  THEN 2
      WHEN a.SegmentoScore=22 AND BR_SCORE_FIN >= 256 THEN 1
      -- 23 THINREVAGEGE30
      WHEN a.SegmentoScore=23 AND BR_SCORE_FIN < 228  THEN 5
      WHEN a.SegmentoScore=23 AND BR_SCORE_FIN < 240  THEN 4
      WHEN a.SegmentoScore=23 AND BR_SCORE_FIN < 251  THEN 3
      WHEN a.SegmentoScore=23 AND BR_SCORE_FIN < 260  THEN 2
      WHEN a.SegmentoScore=23 AND BR_SCORE_FIN >= 260 THEN 1
      -- 24 THINREVTLAGELT30
      WHEN a.SegmentoScore=24 AND BR_SCORE_FIN < 240  THEN 5
      WHEN a.SegmentoScore=24 AND BR_SCORE_FIN < 241  THEN 4
      WHEN a.SegmentoScore=24 AND BR_SCORE_FIN < 246  THEN 3
      WHEN a.SegmentoScore=24 AND BR_SCORE_FIN < 261  THEN 2
      WHEN a.SegmentoScore=24 AND BR_SCORE_FIN >= 261 THEN 1
      -- 33 TDOFFUSEDADGE45
      WHEN a.SegmentoScore=33 AND BR_SCORE_FIN BETWEEN 0 AND 248   THEN 5
      WHEN a.SegmentoScore=33 AND BR_SCORE_FIN BETWEEN 249 AND 266 THEN 4
      WHEN a.SegmentoScore=33 AND BR_SCORE_FIN BETWEEN 267 AND 280 THEN 3
      WHEN a.SegmentoScore=33 AND BR_SCORE_FIN BETWEEN 281 AND 294 THEN 2
      WHEN a.SegmentoScore=33 AND BR_SCORE_FIN >= 295              THEN 1
      -- 34 TDOFFUSEDADLT45
      WHEN a.SegmentoScore=34 AND BR_SCORE_FIN BETWEEN 0 AND 246   THEN 5
      WHEN a.SegmentoScore=34 AND BR_SCORE_FIN BETWEEN 247 AND 259 THEN 4
      WHEN a.SegmentoScore=34 AND BR_SCORE_FIN BETWEEN 260 AND 265 THEN 3
      WHEN a.SegmentoScore=34 AND BR_SCORE_FIN BETWEEN 266 AND 287 THEN 2
      WHEN a.SegmentoScore=34 AND BR_SCORE_FIN >= 288              THEN 1
      -- 35 TDONLY
      WHEN a.SegmentoScore=35 AND BR_SCORE_FIN BETWEEN 0 AND 236   THEN 5
      WHEN a.SegmentoScore=35 AND BR_SCORE_FIN BETWEEN 237 AND 254 THEN 4
      WHEN a.SegmentoScore=35 AND BR_SCORE_FIN BETWEEN 255 AND 268 THEN 3
      WHEN a.SegmentoScore=35 AND BR_SCORE_FIN BETWEEN 269 AND 285 THEN 2
      WHEN a.SegmentoScore=35 AND BR_SCORE_FIN >= 286              THEN 1
      -- 36 PURO
      WHEN a.SegmentoScore=36 AND BR_SCORE_FIN BETWEEN 0 AND 236   THEN 5 
      WHEN a.SegmentoScore=36 AND BR_SCORE_FIN BETWEEN 237 AND 254 THEN 4
      WHEN a.SegmentoScore=36 AND BR_SCORE_FIN BETWEEN 255 AND 268 THEN 3
      WHEN a.SegmentoScore=36 AND BR_SCORE_FIN BETWEEN 269 AND 285 THEN 2
      WHEN a.SegmentoScore=36 AND BR_SCORE_FIN >= 286              THEN 1
      ELSE -999
    END AS RiskLevel

  FROM `MUS_PRO_DWH_SAS_TEMP.DWH_FAC_OMDM_SOLICITUD_APM_PEGA` a        
  LEFT JOIN VFAC_OMDM_FLUJO b
    ON a.BR_SOLIC_CVE = b.BR_SOLIC_CVE
   AND a.BR_TIPO = b.BR_TIPO
  
  LEFT JOIN (
    SELECT
      CTA_CVE,
      BR_SOLIC_CVE,
      BR_TIPO,
      CTA_FCH_ALTA
    FROM `crp-pro-dwh-semanticagold.EIL_DP_VDWH.VDIM_CTA`              
    WHERE CTA_FCH_ALTA >= FCH_INI
      AND TIP_INF IN (200, 210, 230)
  ) c
    ON a.BR_SOLIC_CVE = c.BR_SOLIC_CVE
   AND CAST(SUBSTR(CAST(a.BR_TIPO AS STRING), 1, 3) AS NUMERIC) = c.BR_TIPO
  
  LEFT JOIN `MUS_PRO_DWH_SAS_TEMP.DWH_FAC_APIA_APM_PEGA` d           
    ON a.BR_SOLIC_CVE = d.BR_SOLIC_CVE
   AND a.BR_TIPO = d.BR_TIPO
  
  LEFT JOIN APIS f                                                  
    ON a.BR_SOLIC_CVE = f.BR_SOLIC_CVE
   AND a.BR_TIPO = f.BR_TIPO

  -- [--- DESCOMENTAR SI SE USA TABLA E ---]
  -- LEFT JOIN `crp-pro-dwh-semanticagold.EIL_DP_VMASTER.VFAC_NEGFIN_SOLICITUDES` e 
  --   ON a.BR_SOLIC_CVE = e.BR_SOLIC_CVE AND a.BR_TIPO = e.BR_TIPO

  WHERE a.BR_ORG IN (200, 210, 230)
    AND a.BR_FCH_SOLIC >= FCH_INI
)

-- ==========================================
-- 4. EXTRACCIÓN Y AGREGACIÓN FINAL
-- ==========================================
SELECT
  -- Dimensiones de Agrupación
  Producto,
  Segmento,
  Flujo,
  Canal,
  Tienda,
  ClienteEmpleado,
  Venta,
  DATE_TRUNC(BR_FCH_SOLIC, MONTH) AS MES,
  
  -- Métricas Volumétricas Fundamentales
  COUNT(*) AS Solicitudes,
  
  SUM(IF(
    (BR_STATUS IN ('A','T','E') AND CTA_CVE > 0) OR 
    (BR_STATUS = 'P' AND ESTATUS_SOLICITUD_APLICACION = 'Contratación_PIF' AND CTA_CVE > 0) OR 
    (BR_STATUS = 'B' AND ESTATUS_SOLICITUD_APLICACION IN ('Pendiente_selfie','Pendiente_huella') AND CTA_CVE > 0) OR 
    (BR_STATUS = 'J' AND ESTATUS_SOLICITUD_APLICACION IN ('Aprobado_Creación_Completa_BLCK','Aprobado_BLCK') AND CTA_CVE > 0)
  , 1, 0)) AS Aprobadas,
  
  SUM(IF(CTA_CVE > 0, 1, 0)) AS Cuentas,

  -- Distribución y Perfiles por Hit Buro
  SUM(IF(CTA_CVE > 0 AND BR_HIT_CVE = 1, 1, 0)) AS CuentasHit,
  SUM(IF(CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2), 1, 0)) AS CuentasNHTF,
  
  -- Agregados de Riesgo y Perfil
  SUM(IF(CTA_CVE > 0 AND RiskLevel IN (1, 2), 1, 0)) AS SumLVL,   -- Low Risk Level
  SUM(IF(CTA_CVE > 0 AND RiskLevel IN (4, 5), 1, 0)) AS SumHVH,   -- High Risk Level
  SUM(IF(CTA_CVE > 0, BR_SCORE_FIN, 0)) AS SumScore,
  SUM(IF(CTA_CVE > 0 AND TASA = 0, 1, 0)) AS SumT3,
  
  -- Variables Demográficas (Solo Cuentas Formalizadas)
  SUM(IF(CTA_CVE > 0, BR_EDAD, 0)) AS SumEdad,
  SUM(IF(CTA_CVE > 0 AND BR_SEXO = 'Femenino', 1, 0)) AS SumFemenino,
  SUM(IF(CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2) AND BR_EDC_CVE = '2', 1, 0)) AS SumCasado,
  SUM(IF(CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2) AND BR_TIP_VDA = '1', 1, 0)) AS SumVivPropia,
  SUM(IF(CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2) AND BR_ESCOLARIDAD IN (3, 4), 1, 0)) AS SumLicPos,
  
  -- Métricas de Ocupación e Ingreso
  SUM(CASE 
        WHEN CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2) AND BR_GIRO = '5' THEN 0
        WHEN CTA_CVE > 0 AND BR_HIT_CVE IN (0, 2) THEN 1
        ELSE 0 
      END) AS SumAsalariados,
      
  SUM(IF(CTA_CVE > 0, BR_ING_TOT, 0)) AS SumIngreso,

  /* ---------------------------------------------------------------------------------
  [--- ESPACIO COMENTADO: COMPORTAMIENTO DE BURÓ (DESCOMENTAR SI SE USA TABLA E) ---]
  ---------------------------------------------------------------------------------
  -- SUM(CASE WHEN CTA_CVE > 0 THEN PTI ELSE 0 END) AS SUM_PTI,
  -- SUM(CASE WHEN CTA_CVE > 0 THEN BTI ELSE 0 END) AS SUM_BTI,
  -- SUM(CASE WHEN CTA_CVE > 0 THEN IQ_NUM_CONS_6M ELSE 0 END) AS SUM_IQ_NUM_CONS_6M,
  -- SUM(CASE WHEN CTA_CVE > 0 THEN IQ_NUM_CONS_3M ELSE 0 END) AS SUM_IQ_NUM_CONS_3M,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 AND SEGMENTO_CLIENTE IN ('07. TD + 3+ OffUs','07. VISA + 3+ OffUs') THEN 1 ELSE 0 END) AS N_SEG_CTE_3MASOFFUS,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN TL_NUM_CTAS_TDC_ABT ELSE 0 END) AS N_TARJETAS,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN TL_SUM_SDO_CTAS_TDC_ABT ELSE 0 END) AS SUM_SDO,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN TL_SUM_IMP_PAG_ABT ELSE 0 END) AS SUM_PAG,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN UTILIZACION ELSE 0 END) AS SUM_UTILIZACION,
  -- SUM(CASE WHEN BR_HIT_CVE = 1 AND BR_TIPO_BURO_CONSULTA_CVE = 2 THEN 1 ELSE 0 END) AS N_SOL_CIRCULO,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_TIPO_BURO_CONSULTA_CVE = 2 AND BR_HIT_CVE = 1 THEN 1 ELSE 0 END) AS N_CTA_CIRCULO,
  */

  /* ---------------------------------------------------------------------------------
  [--- ESPACIO COMENTADO: DETALLE DE LÍNEAS ONUS VS OFFUS (DESCOMENTAR SI SE USA) ---]
  ---------------------------------------------------------------------------------
  -- SUM(CASE WHEN CTA_CVE > 0 THEN BR_IMP_LIM_CRED ELSE 0 END) AS SUM_LINEA_ONUS,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN BR_IMP_LIM_CRED ELSE 0 END) AS SUM_LINEA_ONUS_HIT,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 AND LINEAS > 0 THEN LINEAS ELSE 0 END) AS SUM_LINEA_OFFUS,
  -- SUM(CASE WHEN CTA_CVE > 0 AND BR_HIT_CVE = 1 THEN LTI_TOT ELSE 0 END) AS SUM_LTI_TOTAL,
  */
  
  -- Líneas de Crédito y Ratios Activos
  SUM(CASE WHEN CTA_CVE > 0 THEN LTI_ONUS ELSE 0 END) AS SUM_LTI_ONUS,
  SUM(IF(CTA_CVE > 0, BR_IMP_LIM_CRED, 0)) AS SUM_SDO_LIM_CRED

FROM SOLICITUDES
WHERE TDA_CVE IN ('0597', '0551', '0782')                             -- <--- Filtro de Tiendas Objetivo del Piloto
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;
