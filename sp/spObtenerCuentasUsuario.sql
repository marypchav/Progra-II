CREATE OR ALTER   PROCEDURE [dbo].[spObtenerCuentasUsuario]
    @IdUsuario INT -- de qué usuario se piden las cuentas
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- se une cada cuenta con su dueño (Persona), su tipo de cuenta y la moneda del tipo, para que el sitio muestre datos legibles (nombre del dueño, tipo, símbolo) y no solo Ids

    SELECT C.IdCuenta, C.NumeroCuenta, P.Nombre AS NombreDueno
         , TC.Nombre AS TipoCuenta, M.Simbolo, C.Saldo, C.FechaCreacion
    FROM dbo.Cuenta AS C
    JOIN dbo.Persona          AS P  ON P.IdPersona = C.IdPersonaDueno
    JOIN dbo.TipoCuentaAhorro AS TC ON TC.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro
    JOIN dbo.TipoMoneda       AS M  ON M.IdTipoMoneda = TC.IdTipoMoneda

    -- verifica el acceso. el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer

    WHERE EXISTS (SELECT 1 FROM dbo.Usuario AS U
                  WHERE U.IdUsuario = @IdUsuario AND U.EsAdministrador = 1)
       OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer AS V
                  WHERE V.IdUsuario = @IdUsuario AND V.IdCuenta = C.IdCuenta)
    ORDER BY C.NumeroCuenta; -- orden estable para mostrar la lista
END;
GO