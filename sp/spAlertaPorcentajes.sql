CREATE OR ALTER   PROCEDURE [dbo].[spAlertaPorcentajes]
    @IdUsuario     INT -- quién consulta. sirve para verificar el acceso
    , @IdCuenta    INT -- de qué cuenta se revisan los porcentajes
    , @OutResultCode INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito

    -- validar que la cuenta exista

    IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
    BEGIN SET @OutResultCode = 50014; RETURN; END

    -- luego que el usuario sea administrador o tenga esa cuenta en UsuarioPuedeVer

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                   WHERE U.IdUsuario = @IdUsuario
                     AND (U.EsAdministrador = 1
                          OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                     WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
    BEGIN SET @OutResultCode = 50002; RETURN; END

    -- calcula la suma y la bandera de alerta.
    -- ISNULL(SUM(...), 0): si la cuenta no tiene beneficiarios activos, SUM devuelve NULL. se convierte en 0 para que también cuente como que no suma 100 y dispare la alerta.
    -- SumaPorcentajes: el total
    -- MostrarAlerta: 1 si la suma es distinta de 100, 0 si es exactamente 100

    SELECT ISNULL(SUM(B.Porcentaje), 0) AS SumaPorcentajes 
         , CAST(CASE WHEN ISNULL(SUM(B.Porcentaje), 0) <> 100 THEN 1 ELSE 0 END AS BIT) AS MostrarAlerta -- CAST - AS BIT convierte el resultado en verdadero/falso
    FROM dbo.Beneficiario AS B
    WHERE B.IdCuenta = @IdCuenta AND B.FlagActivo = 1;
END;
GO