CREATE OR ALTER PROCEDURE dbo.spEliminarBeneficiario
    @inIdUsuario INT -- quién elimina, para el acceso y la bitácora
    , @inIdBeneficiario INT -- cuál beneficiario se elimina
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spEliminarBeneficiario
        @inIdUsuario = 1
        , @inIdBeneficiario = 1
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionEliminar INT = 5; -- TipoOperacion "Eliminar beneficiario"

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idCuenta INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idCuenta = NULL;

        -- validaciones
        -- busca el beneficiario activo y obtiene su cuenta
        SELECT @idCuenta = B.IdCuenta
        FROM dbo.Beneficiario AS B
        WHERE (B.IdBeneficiario = @inIdBeneficiario)
            AND (B.FlagActivo = @true);

        IF (@idCuenta IS NULL)
        BEGIN
            SET @outResultCode = 50013; -- no existe o ya está inactivo
            RETURN;
        END;

        -- el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario);

        IF (@esAdministrador = @false)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.UsuarioPuedeVer AS UPV
                WHERE (UPV.IdUsuario = @inIdUsuario)
                    AND (UPV.IdCuenta = @idCuenta)
            )
        BEGIN
            SET @outResultCode = 50002; -- sin acceso a la cuenta
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @fechaDesactivacion DATETIME
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        -- la fecha se calcula una vez y se usa igual en el UPDATE y en el JSON
        SET @fechaDesactivacion = GETDATE();

        -- JSON con el estado antes (FlagActivo = 1)
        SET @jsonAntes = (
            SELECT B.IdBeneficiario
                , C.NumeroCuenta
                , P.ValorDocumentoIdentidad
                , P.Nombre
                , PA.Nombre AS Parentesco
                , B.Porcentaje
                , B.FlagActivo
                , B.FechaDesactivacion
            FROM dbo.Beneficiario AS B
            INNER JOIN dbo.Cuenta AS C
                ON (C.IdCuenta = B.IdCuenta)
            INNER JOIN dbo.Persona AS P
                ON (P.IdPersona = B.IdPersonaBeneficiario)
            INNER JOIN dbo.Parentesco AS PA
                ON (PA.IdParentesco = B.IdParentesco)
            WHERE (B.IdBeneficiario = @inIdBeneficiario)
            FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
        );

        -- JSON con el estado después (FlagActivo = 0 y con fecha de desactivación)
        SET @jsonDespues = (
            SELECT B.IdBeneficiario
                , C.NumeroCuenta
                , P.ValorDocumentoIdentidad
                , P.Nombre
                , PA.Nombre AS Parentesco
                , B.Porcentaje
                , @false AS FlagActivo
                , @fechaDesactivacion AS FechaDesactivacion
            FROM dbo.Beneficiario AS B
            INNER JOIN dbo.Cuenta AS C
                ON (C.IdCuenta = B.IdCuenta)
            INNER JOIN dbo.Persona AS P
                ON (P.IdPersona = B.IdPersonaBeneficiario)
            INNER JOIN dbo.Parentesco AS PA
                ON (PA.IdParentesco = B.IdParentesco)
            WHERE (B.IdBeneficiario = @inIdBeneficiario)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- transacción: la eliminación lógica y la bitácora van juntas
        BEGIN TRANSACTION tEliminarBeneficiario;

            UPDATE dbo.Beneficiario
            SET FlagActivo = @false
                , FechaDesactivacion = @fechaDesactivacion
            WHERE (IdBeneficiario = @inIdBeneficiario);

            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionEliminar
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tEliminarBeneficiario;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

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
