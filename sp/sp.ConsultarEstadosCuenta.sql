CREATE OR ALTER PROCEDURE dbo.spConsultarEstadosCuenta
    @IdUsuario     INT
    , @IdCuenta    INT
    , @IP          VARCHAR(64)
    , @OutResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
        BEGIN SET @OutResultCode = 50014; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario, 7, @IP, NULL,
                (SELECT C.NumeroCuenta FROM dbo.Cuenta AS C WHERE C.IdCuenta = @IdCuenta
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

        SELECT TOP (8)
               E.IdEstadoCuenta, E.FechaInicio, E.FechaFin, E.FechaEmision
             , E.SaldoInicial, E.SaldoFinal, E.SaldoMinimo, E.InteresesAcumulados
             , E.CantRetiros, E.CantDepositos
             , E.CantSinpeEntrantes, E.CantSinpeSalientes
        FROM dbo.EstadoCuenta AS E
        WHERE E.IdCuenta = @IdCuenta
        ORDER BY E.FechaEmision DESC, E.IdEstadoCuenta DESC;
    END TRY
    BEGIN CATCH
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO