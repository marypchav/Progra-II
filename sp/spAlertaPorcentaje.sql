CREATE OR ALTER PROCEDURE dbo.spAlertaPorcentaje
    @inIdUsuario INT -- quién consulta, para verificar el acceso
    , @inIdCuenta INT -- de qué cuenta se revisan los porcentajes
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAlertaPorcentaje
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
            , @false BIT = 0
            , @sumaEsperada INT = 100;

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @sumaPorcentajes INT;

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @sumaPorcentajes = 0;

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

        -- preprocesamiento: suma de porcentajes de los beneficiarios activos.
        -- si no hay beneficiarios activos, SUM devuelve NULL; ISNULL lo convierte
        -- en 0 para que también dispare la alerta
        SELECT @sumaPorcentajes = ISNULL(SUM(B.Porcentaje), 0)
        FROM dbo.Beneficiario AS B
        WHERE (B.IdCuenta = @inIdCuenta)
            AND (B.FlagActivo = @true);

        -- resultado para la capa lógica
        SELECT @sumaPorcentajes AS SumaPorcentajes
            , CASE
                WHEN (@sumaPorcentajes <> @sumaEsperada) THEN @true
                ELSE @false
              END AS MostrarAlerta;

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
