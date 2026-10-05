CREATE OR ALTER   PROCEDURE [dbo].[spActualizarBeneficiario]
    @IdUsuario          INT -- quién edita. sirve para verificar el acceso y para la bitácora
    , @IdBeneficiario   INT -- cuál beneficiario se edita 
    , @IP               VARCHAR(64) -- IP del cliente, para la bitácora
    , @Nombre           VARCHAR(64) -- nuevo nombre 
    , @FechaNacimiento  DATE -- nueva fecha de nacimiento
    , @Email            VARCHAR(64) -- nuevo email
    , @Telefono1        VARCHAR(64) -- nuevo teléfono 1
    , @Telefono2        VARCHAR(64) -- nuevo teléfono 2
    , @IdParentesco     INT -- nuevo parentesco 
    , @Porcentaje       INT -- nuevo porcentaje del 1 al 100
    , @OutResultCode    INT OUTPUT -- parámetro de salida: 0 = éxito, otro = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito; cada error lo cambia antes de salir
    BEGIN TRY
        DECLARE @IdCuenta INT, @IdPersona INT; -- se llenan al buscar el beneficiario

        -- busca el beneficiario ACTIVO y obtiene de él su cuenta y su persona.
        -- la cuenta se deduce aquí (y no se recibe como parámetro) para que nadie pueda enviar un beneficiario de una cuenta junto con otra cuenta.
        -- el FlagActivo = 1 evita editar uno ya eliminado
        .
        SELECT @IdCuenta = B.IdCuenta, @IdPersona = B.IdPersonaBeneficiario
        FROM dbo.Beneficiario AS B
        WHERE B.IdBeneficiario = @IdBeneficiario AND B.FlagActivo = 1;

        -- si no se encontró, el beneficiario no existe o está inactivo
        IF @IdCuenta IS NULL
        BEGIN SET @OutResultCode = 50013; RETURN; END

        -- verifica el acceso: el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer. Sin esto, un cliente podría editar
        -- beneficiarios de cuentas ajenas solo cambiando el id

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        -- validación de campos 
        -- primero se limpian los espacios al inicio y al final; ISNULL convierte un NULL en texto vacío para que las validaciones de abajo lo puedan detectar
        
        SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
        SET @Email = LTRIM(RTRIM(ISNULL(@Email, '')));
        SET @Telefono1 = LTRIM(RTRIM(ISNULL(@Telefono1, '')));
        SET @Telefono2 = LTRIM(RTRIM(ISNULL(@Telefono2, '')));

        -- validación de nombre obligatorio

        IF @Nombre = ''
        BEGIN SET @OutResultCode = 50004; RETURN; END

        -- porcentaje entero entre 1 y 100, solo se valida el rango individual

        IF @Porcentaje IS NULL OR @Porcentaje NOT BETWEEN 1 AND 100
        BEGIN SET @OutResultCode = 50006; RETURN; END

        -- el parentesco debe existir en el catálogo (es una llave foránea)

        IF NOT EXISTS (SELECT 1 FROM dbo.Parentesco WHERE IdParentesco = @IdParentesco)
        BEGIN SET @OutResultCode = 50007; RETURN; END

        -- validar que la fecha de nacimiento no esté vacía, no sea futura y tampoco super antigua

        IF @FechaNacimiento IS NULL OR @FechaNacimiento > CAST(GETDATE() AS DATE)
           OR @FechaNacimiento < '1900-01-01'
        BEGIN SET @OutResultCode = 50009; RETURN; END

        -- email con formato básico de blabla@blabla.blabla y sin espacios

        IF @Email NOT LIKE '%_@_%._%' OR @Email LIKE '% %'
        BEGIN SET @OutResultCode = 50010; RETURN; END

        -- teléfonos obligatorios y solo con dígitos 

        IF @Telefono1 = '' OR @Telefono1 LIKE '%[^0-9]%'
           OR @Telefono2 = '' OR @Telefono2 LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50011; RETURN; END

        -- se compara lo recibido contra lo que hay guardado.
        -- @CambioPorc: cambió el porcentaje.
        -- @CambioOtros: cambió cualquier otro dato.
        -- sirve para no registrar en bitácora si no hubo cambios, y escoger el tipo de operación (6 = solo porcentaje, 4 = otros cambios).
        DECLARE @CambioPorc BIT = 0, @CambioOtros BIT = 0;

        SELECT @CambioPorc = CASE WHEN B.Porcentaje <> @Porcentaje THEN 1 ELSE 0 END
             , @CambioOtros = CASE WHEN P.Nombre <> @Nombre
                                     OR P.FechaNacimiento <> @FechaNacimiento
                                     OR P.Email <> @Email
                                     OR P.Telefono1 <> @Telefono1
                                     OR P.Telefono2 <> @Telefono2
                                     OR B.IdParentesco <> @IdParentesco
                                   THEN 1 ELSE 0 END
        FROM dbo.Beneficiario AS B
        JOIN dbo.Persona AS P ON P.IdPersona = B.IdPersonaBeneficiario
        WHERE B.IdBeneficiario = @IdBeneficiario;

        -- si no cambió nada, se sale con éxito

        IF @CambioPorc = 0 AND @CambioOtros = 0
            RETURN; -- nada que actualizar, no se registra en bitácora

        -- desde aquí se modifican datos, así que se abre una transacción en donde o se guardan TODOS los cambios (persona, beneficiario y bitácora) o ninguno

        BEGIN TRANSACTION;

        -- JSON con el estado ANTES del cambio porque el doc pide guardar "antes y después" de cada modificación de beneficiarios. 

        DECLARE @JsonAntes NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, P.FechaNacimiento
              , P.Email, P.Telefono1, P.Telefono2, B.FlagActivo
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        -- actualiza los datos personales en Persona 

        UPDATE dbo.Persona
        SET Nombre = @Nombre, FechaNacimiento = @FechaNacimiento
          , Email = @Email, Telefono1 = @Telefono1, Telefono2 = @Telefono2
        WHERE IdPersona = @IdPersona;

        -- actualiza la relación cuenta-beneficiario con el parentesco y porcentaje

        UPDATE dbo.Beneficiario
        SET IdParentesco = @IdParentesco, Porcentaje = @Porcentaje
        WHERE IdBeneficiario = @IdBeneficiario;

        -- JSON con el estado DESPUÉS del cambio (lo mismo pero con los datos nuevos)
        DECLARE @JsonDespues NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, P.FechaNacimiento
              , P.Email, P.Telefono1, P.Telefono2, B.FlagActivo
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        -- registra en la bitácora. 

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario,
                CASE WHEN @CambioOtros = 0 THEN 6 ELSE 4 END,
                @IP, @JsonAntes, @JsonDespues);

        -- se confirman los cambios de forma definitiva

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

        -- cualquier error random cae aquí

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError; -- devuelve el texto del error para depurar
    END CATCH
END;
GO