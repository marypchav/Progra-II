CREATE OR ALTER   PROCEDURE [dbo].[spConsultarEstadosCuenta]
    @IdUsuario     INT -- quién consulta. sirve para verificar el acceso y para la bitácora
    , @IdCuenta    INT -- de qué cuenta se piden los estados
    , @IP          VARCHAR(64) -- ip del cliente, para la bitácora
    , @OutResultCode INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito
    BEGIN TRY

        -- la cuenta debe existir

        IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
        BEGIN SET @OutResultCode = 50014; RETURN; END

        -- verifica el acceso. el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        -- registra la consulta en la bitácora (IdTipoOperacion 7 = Consultar estado de cuenta).
        -- DatosAntes queda en NULL
        -- en DatosDespues se guarda el número de cuenta consultada.
        -- se registra antes de devolver los datos y solo si el acceso fue permitido, así que los intentos rechazados no quedan en la bitácora

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario, 7, @IP, NULL,
                (SELECT C.NumeroCuenta FROM dbo.Cuenta AS C WHERE C.IdCuenta = @IdCuenta
                 FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

        -- devuelve los últimos 8 estados. TOP (8) limita las filas, y el ORDER BY (de la fecha de emisión más reciente a la más antigua) decide cuáles son los últimos

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