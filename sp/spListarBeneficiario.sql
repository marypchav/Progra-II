CREATE OR ALTER PROCEDURE dbo.spListarBeneficiario
    @inIdUsuario INT -- quién consulta, para verificar el acceso
    , @inIdCuenta INT -- de qué cuenta se listan los beneficiarios
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spListarBeneficiario
        @inIdUsuario = 1
        , @inIdCuenta = 1
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

        -- validaciones
        -- la cuenta debe existir
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Cuenta AS C
            WHERE (C.IdCuenta = @inIdCuenta)
        )
        BEGIN
            SET @outResultCode = 50014; -- cuenta no existe
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
                    AND (UPV.IdCuenta = @inIdCuenta)
            )
        BEGIN
            SET @outResultCode = 50002; -- sin acceso a la cuenta
            RETURN;
        END;

        -- devuelve los beneficiarios activos. Beneficiario solo guarda la relación
        -- cuenta-persona, por eso se une con Persona (datos personales) y con
        -- Parentesco (nombre del parentesco)
        SELECT B.IdBeneficiario
            , P.IdTipoDocuIdentidad
            , P.ValorDocumentoIdentidad
            , P.Nombre
            , B.IdParentesco
            , PA.Nombre AS Parentesco
            , B.Porcentaje
            , P.FechaNacimiento
            , P.Email
            , P.Telefono1
            , P.Telefono2
        FROM dbo.Beneficiario AS B
        INNER JOIN dbo.Persona AS P
            ON (P.IdPersona = B.IdPersonaBeneficiario)
        INNER JOIN dbo.Parentesco AS PA
            ON (PA.IdParentesco = B.IdParentesco)
        WHERE (B.IdCuenta = @inIdCuenta)
            AND (B.FlagActivo = @true)
        ORDER BY B.IdBeneficiario; -- orden estable: el más antiguo primero

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
