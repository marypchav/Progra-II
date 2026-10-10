CREATE OR ALTER PROCEDURE dbo.spAgregarBeneficiario
    @inIdUsuario INT -- quién agrega, para el acceso y la bitácora
    , @inIdCuenta INT -- a qué cuenta se agrega el beneficiario
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inIdTipoDocuIdentidad INT -- tipo de documento
    , @inValorDocumento VARCHAR(32) -- número de documento (solo dígitos)
    , @inNombre VARCHAR(64) -- nombre del beneficiario
    , @inFechaNacimiento DATE -- fecha de nacimiento
    , @inEmail VARCHAR(64) -- email
    , @inTelefono1 VARCHAR(64) -- teléfono 1
    , @inTelefono2 VARCHAR(64) -- teléfono 2
    , @inIdParentesco INT -- parentesco con el dueño de la cuenta
    , @inPorcentaje INT -- porcentaje de beneficio (1 a 100)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAgregarBeneficiario
        @inIdUsuario = 1
        , @inIdCuenta = 1
        , @inIP = '127.0.0.1'
        , @inIdTipoDocuIdentidad = 1
        , @inValorDocumento = '204560789'
        , @inNombre = 'Maria Mora Solis'
        , @inFechaNacimiento = '1990-05-20'
        , @inEmail = 'maria@gmail.com'
        , @inTelefono1 = '88112233'
        , @inTelefono2 = '24197545'
        , @inIdParentesco = 2
        , @inPorcentaje = 20
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionAgregar INT = 3 -- TipoOperacion "Agregar beneficiario"
            , @maxBeneficiarios INT = 3 -- máximo de beneficiarios activos
            , @fechaMinima DATE = '1900-01-01'; -- fecha de nacimiento más antigua aceptada

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @valorDocumento VARCHAR(32)
            , @nombre VARCHAR(64)
            , @fechaNacimiento DATE
            , @email VARCHAR(64)
            , @telefono1 VARCHAR(64)
            , @telefono2 VARCHAR(64);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;

        -- se limpian espacios al inicio y al final; ISNULL convierte un NULL en
        -- texto vacío para que las validaciones de abajo lo detecten
        SET @valorDocumento = LTRIM(RTRIM(ISNULL(@inValorDocumento, '')));
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @fechaNacimiento = @inFechaNacimiento;
        SET @email = LTRIM(RTRIM(ISNULL(@inEmail, '')));
        SET @telefono1 = LTRIM(RTRIM(ISNULL(@inTelefono1, '')));
        SET @telefono2 = LTRIM(RTRIM(ISNULL(@inTelefono2, '')));

        -- validaciones de acceso
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

        -- validaciones de campos
        -- nombre obligatorio
        IF (@nombre = '')
        BEGIN
            SET @outResultCode = 50004;
            RETURN;
        END;

        -- documento obligatorio y solo con dígitos
        IF (@valorDocumento = '')
            OR (@valorDocumento LIKE '%[^0-9]%')
        BEGIN
            SET @outResultCode = 50005;
            RETURN;
        END;

        -- porcentaje entero entre 1 y 100
        IF (@inPorcentaje IS NULL)
            OR (@inPorcentaje NOT BETWEEN 1 AND 100)
        BEGIN
            SET @outResultCode = 50006;
            RETURN;
        END;

        -- el parentesco debe existir en el catálogo
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Parentesco AS PA
            WHERE (PA.IdParentesco = @inIdParentesco)
        )
        BEGIN
            SET @outResultCode = 50007;
            RETURN;
        END;

        -- el tipo de documento debe existir en el catálogo
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.TipoDocuIdentidad AS TDI
            WHERE (TDI.IdTipoDocuIdentidad = @inIdTipoDocuIdentidad)
        )
        BEGIN
            SET @outResultCode = 50008;
            RETURN;
        END;

        -- fecha de nacimiento: obligatoria, no futura y no anterior a 1900
        IF (@fechaNacimiento IS NULL)
            OR (@fechaNacimiento > CAST(GETDATE() AS DATE))
            OR (@fechaNacimiento < @fechaMinima)
        BEGIN
            SET @outResultCode = 50009;
            RETURN;
        END;

        -- email con formato básico algo@algo.algo y sin espacios
        IF (@email NOT LIKE '%_@_%._%')
            OR (@email LIKE '% %')
        BEGIN
            SET @outResultCode = 50010;
            RETURN;
        END;

        -- teléfonos obligatorios y solo con dígitos
        IF (@telefono1 = '')
            OR (@telefono1 LIKE '%[^0-9]%')
            OR (@telefono2 = '')
            OR (@telefono2 LIKE '%[^0-9]%')
        BEGIN
            SET @outResultCode = 50011;
            RETURN;
        END;

        -- la persona no puede ser ya beneficiario activo de la misma cuenta.
        -- va antes del máximo de 3 porque es el mensaje más preciso para el usuario
        IF EXISTS (
            SELECT 1
            FROM dbo.Beneficiario AS B
            INNER JOIN dbo.Persona AS P
                ON (P.IdPersona = B.IdPersonaBeneficiario)
            WHERE (B.IdCuenta = @inIdCuenta)
                AND (P.ValorDocumentoIdentidad = @valorDocumento)
                AND (B.FlagActivo = @true)
        )
        BEGIN
            SET @outResultCode = 50012;
            RETURN;
        END;

        -- máximo 3 beneficiarios activos por cuenta. los eliminados
        -- (FlagActivo = 0) no cuentan, así que eliminar uno libera un espacio
        IF (
            SELECT COUNT(1)
            FROM dbo.Beneficiario AS B
            WHERE (B.IdCuenta = @inIdCuenta)
                AND (B.FlagActivo = @true)
        ) >= @maxBeneficiarios
        BEGIN
            SET @outResultCode = 50003;
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @existePersona BIT
            , @numeroCuenta VARCHAR(20)
            , @nombreParentesco VARCHAR(32)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @existePersona = @false;

        -- si la persona ya existe se reutiliza y se usan sus datos guardados
        -- (los campos comunes de una persona existen una sola vez)
        SELECT @existePersona = @true
            , @nombre = P.Nombre
            , @fechaNacimiento = P.FechaNacimiento
            , @email = P.Email
            , @telefono1 = P.Telefono1
            , @telefono2 = P.Telefono2
        FROM dbo.Persona AS P
        WHERE (P.ValorDocumentoIdentidad = @valorDocumento);

        SELECT @numeroCuenta = C.NumeroCuenta
        FROM dbo.Cuenta AS C
        WHERE (C.IdCuenta = @inIdCuenta);

        SELECT @nombreParentesco = PA.Nombre
        FROM dbo.Parentesco AS PA
        WHERE (PA.IdParentesco = @inIdParentesco);

        -- JSON con el estado después de agregar (antes no existía nada)
        SET @jsonDespues = (
            SELECT @numeroCuenta AS NumeroCuenta
                , @valorDocumento AS ValorDocumentoIdentidad
                , @nombre AS Nombre
                , @nombreParentesco AS Parentesco
                , @inPorcentaje AS Porcentaje
                , @fechaNacimiento AS FechaNacimiento
                , @email AS Email
                , @telefono1 AS Telefono1
                , @telefono2 AS Telefono2
                , @true AS FlagActivo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- transacción: se guardan todos los cambios (persona, beneficiario y
        -- bitácora) o ninguno. Sin IF: el filtro del WHERE decide si se inserta
        BEGIN TRANSACTION tAgregarBeneficiario;

            -- la persona se inserta solo si no existía
            INSERT INTO dbo.Persona (
                IdTipoDocuIdentidad
                , ValorDocumentoIdentidad
                , Nombre
                , FechaNacimiento
                , Email
                , Telefono1
                , Telefono2
            )
            SELECT @inIdTipoDocuIdentidad
                , @valorDocumento
                , @nombre
                , @fechaNacimiento
                , @email
                , @telefono1
                , @telefono2
            WHERE (@existePersona = @false);

            -- relación cuenta-beneficiario; la persona se obtiene por su documento
            INSERT INTO dbo.Beneficiario (
                IdCuenta
                , IdPersonaBeneficiario
                , IdParentesco
                , Porcentaje
            )
            SELECT @inIdCuenta
                , P.IdPersona
                , @inIdParentesco
                , @inPorcentaje
            FROM dbo.Persona AS P
            WHERE (P.ValorDocumentoIdentidad = @valorDocumento);

            -- bitácora: DatosAntes en NULL porque antes no existía
            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @tipoOperacionAgregar
                , @inIP
                , NULL
                , @jsonDespues
            );

        COMMIT TRANSACTION tAgregarBeneficiario;

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