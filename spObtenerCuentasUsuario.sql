CREATE OR ALTER PROCEDURE dbo.spObtenerCuentasUsuario
    @IdUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT C.IdCuenta, C.NumeroCuenta, P.Nombre AS NombreDueno
         , TC.Nombre AS TipoCuenta, M.Simbolo, C.Saldo, C.FechaCreacion
    FROM dbo.Cuenta AS C
    JOIN dbo.Persona          AS P  ON P.IdPersona = C.IdPersonaDueno
    JOIN dbo.TipoCuentaAhorro AS TC ON TC.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro
    JOIN dbo.TipoMoneda       AS M  ON M.IdTipoMoneda = TC.IdTipoMoneda
    WHERE EXISTS (SELECT 1 FROM dbo.Usuario AS U
                  WHERE U.IdUsuario = @IdUsuario AND U.EsAdministrador = 1)
       OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer AS V
                  WHERE V.IdUsuario = @IdUsuario AND V.IdCuenta = C.IdCuenta)
    ORDER BY C.NumeroCuenta;
END;
GO