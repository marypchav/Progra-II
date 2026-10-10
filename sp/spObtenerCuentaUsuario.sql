CREATE OR ALTER PROCEDURE dbo.spObtenerCuentaUsuario
    @inIdUsuario INT -- de qué usuario se piden las cuentas
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spObtenerCuentaUsuario
        @inIdUsuario = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0;

        -- variables de uso general
        DECLARE @esAdministrador BIT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;

        -- preprocesamiento: se averigua una sola vez si el usuario es administrador
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario);

        -- se une cada cuenta con su dueño, su tipo de cuenta y la moneda del tipo,
        -- para que el sitio muestre datos legibles y no solo Ids.
        -- el administrador ve todas; el cliente solo las que tiene en UsuarioPuedeVer
        SELECT C.IdCuenta
            , C.NumeroCuenta
            , P.Nombre AS NombreDueno
            , TCA.Nombre AS TipoCuenta
            , TM.Simbolo
            , C.Saldo
            , C.FechaCreacion
        FROM dbo.Cuenta AS C
        INNER JOIN dbo.Persona AS P
            ON (P.IdPersona = C.IdPersonaDueno)
        INNER JOIN dbo.TipoCuentaAhorro AS TCA
            ON (TCA.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro)
        INNER JOIN dbo.TipoMoneda AS TM
            ON (TM.IdTipoMoneda = TCA.IdTipoMoneda)
        WHERE (@esAdministrador = @true)
            OR EXISTS (
                SELECT 1
                FROM dbo.UsuarioPuedeVer AS UPV
                WHERE (UPV.IdUsuario = @inIdUsuario)
                    AND (UPV.IdCuenta = C.IdCuenta)
            )
        ORDER BY C.NumeroCuenta; -- orden estable para mostrar la lista

    END TRY
    BEGIN CATCH

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO
