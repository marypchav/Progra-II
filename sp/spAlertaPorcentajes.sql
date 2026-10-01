CREATE OR ALTER PROCEDURE dbo.spAlertaPorcentajes
    @IdUsuario     INT
    , @IdCuenta    INT
    , @OutResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
    BEGIN SET @OutResultCode = 50014; RETURN; END

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                   WHERE U.IdUsuario = @IdUsuario
                     AND (U.EsAdministrador = 1
                          OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                     WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
    BEGIN SET @OutResultCode = 50002; RETURN; END

    SELECT ISNULL(SUM(B.Porcentaje), 0) AS SumaPorcentajes
         , CAST(CASE WHEN ISNULL(SUM(B.Porcentaje), 0) <> 100 THEN 1 ELSE 0 END AS BIT) AS MostrarAlerta
    FROM dbo.Beneficiario AS B
    WHERE B.IdCuenta = @IdCuenta AND B.FlagActivo = 1;
END;
GO