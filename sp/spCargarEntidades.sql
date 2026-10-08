CREATE OR ALTER   PROCEDURE [dbo].[spCargarEntidades]
AS
BEGIN
    SET NOCOUNT ON;   -- evita mensajes de "N filas afectadas"
    BEGIN TRY
        DECLARE @datos XML; -- contenido completo del XML
        DECLARE @esperadas INT; -- filas que trae el XML para el bloque actual
        DECLARE @insertadas INT; -- filas que realmente se insertaron
        DECLARE @msg NVARCHAR(200); -- mensaje de error si no coinciden

        -- lee el archivo como binario (SINGLE_BLOB) y lo convierte a XML, respetando el UTF-8 declarado

        SELECT @datos = BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\no_catalogos.xml', SINGLE_BLOB) AS x;

        -- todas las cargas van en una transacción, si algo falla no queda nada a medias

        BEGIN TRANSACTION;

        -- personas (dueños de cuenta, beneficiarios y el administrador).

        SET @esperadas = @datos.value('count(//Personas/Persona)', 'INT');

        INSERT INTO dbo.Persona
            (IdTipoDocuIdentidad, ValorDocumentoIdentidad, Nombre,
             FechaNacimiento, Email, Telefono1, Telefono2)
        SELECT Node.value('@TipoDocuIdentidad', 'INT')
             , Node.value('@ValorDocumentoIdentidad', 'VARCHAR(32)') 
             , Node.value('@Nombre', 'VARCHAR(64)') 
             , Node.value('@FechaNacimiento', 'DATE')
             , Node.value('@Email', 'VARCHAR(64)')
             , Node.value('@telefono1', 'VARCHAR(64)') 
             , Node.value('@telefono2', 'VARCHAR(64)')
        FROM @datos.nodes('//Personas/Persona') AS T(Node);

        SET @insertadas = @@ROWCOUNT; -- se guarda de inmediato, cualquier otra instrucción lo reinicia
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('Personas: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas);
            THROW 51001, @msg, 1;
        END

        -- usuarios. El XML trae el documento de la persona asociada con ValorDocId

        SET @esperadas = @datos.value('count(//Usuarios/Usuario)', 'INT');

        INSERT INTO dbo.Usuario (UserName, Pass, EsAdministrador, IdPersona)
        SELECT X.UserName, X.Pass, X.EsAdministrador, P.IdPersona
        FROM (
            SELECT Node.value('@User', 'VARCHAR(64)') AS UserName
                 , Node.value('@Pass', 'VARCHAR(64)') AS Pass
                 , Node.value('@EsAdministrador', 'BIT') AS EsAdministrador   -- 1 = administrador
                 , Node.value('@ValorDocId', 'VARCHAR(32)') AS Doc
            FROM @datos.nodes('//Usuarios/Usuario') AS T(Node)
        ) AS X
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        SET @insertadas = @@ROWCOUNT;
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('Usuarios: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas, ' (revise ValorDocId)');
            THROW 51002, @msg, 1;
        END

        -- cuentas. El documento del cliente se traduce a IdPersonaDueno con el JOIN

        SET @esperadas = @datos.value('count(//Cuentas/Cuenta)', 'INT');

        INSERT INTO dbo.Cuenta
            (NumeroCuenta, IdPersonaDueno, IdTipoCuentaAhorro, FechaCreacion, Saldo)
        SELECT X.NumeroCuenta, P.IdPersona, X.TipoCuentaId, X.FechaCreacion, X.Saldo
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@ValorDocumentoIdentidadDelCliente', 'VARCHAR(32)') AS Doc
                 , Node.value('@TipoCuentaId', 'INT') AS TipoCuentaId
                 , Node.value('@FechaCreacion', 'DATE') AS FechaCreacion
                 , Node.value('@Saldo', 'MONEY') AS Saldo
            FROM @datos.nodes('//Cuentas/Cuenta') AS T(Node)
        ) AS X
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        SET @insertadas = @@ROWCOUNT;
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('Cuentas: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas, ' (revise el documento del cliente)');
            THROW 51003, @msg, 1;
        END

        -- beneficiarios
        SET @esperadas = @datos.value('count(//Beneficiarios/Beneficiario)', 'INT');

        INSERT INTO dbo.Beneficiario (IdCuenta, IdPersonaBeneficiario, IdParentesco, Porcentaje)
        SELECT C.IdCuenta, P.IdPersona, X.IdParentezco, X.Porcentaje
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@ValorDocumentoIdentidadBeneficiario', 'VARCHAR(32)') AS Doc
                 , Node.value('@IdParentezco', 'INT') AS IdParentezco
                 , Node.value('@Porcentaje', 'INT') AS Porcentaje
            FROM @datos.nodes('//Beneficiarios/Beneficiario') AS T(Node)
        ) AS X
        JOIN dbo.Cuenta  AS C ON C.NumeroCuenta = X.NumeroCuenta
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        SET @insertadas = @@ROWCOUNT;
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('Beneficiarios: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas, ' (revise cuenta o documento)');
            THROW 51004, @msg, 1;
        END

        -- estados de cuenta. Ahora el XML también trae los intereses y las cantidades de retiros, depósitos y SINPE, así que se cargan en vez de dejar el DEFAULT 0

        SET @esperadas = @datos.value('count(//Estados_de_Cuenta/Estado_de_Cuenta)', 'INT');

        INSERT INTO dbo.EstadoCuenta
            (IdCuenta, FechaInicio, FechaFin, SaldoInicial, SaldoFinal, SaldoMinimo, FechaEmision
             , InteresesAcumulados, CantRetiros, CantDepositos, CantSinpeEntrantes, CantSinpeSalientes)
        SELECT C.IdCuenta, X.FechaInicio, X.FechaFin, X.SaldoInicial, X.SaldoFinal, X.SaldoMinimo
             , X.FechaFin
             , X.InteresesAcumulados, X.CantRetiros, X.CantDepositos
             , X.CantSinpeEntrantes, X.CantSinpeSalientes
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@fechaInicio', 'DATE') AS FechaInicio
                 , Node.value('@fechafin', 'DATE') AS FechaFin
                 , Node.value('@saldoinicial', 'MONEY') AS SaldoInicial
                 , Node.value('@saldoMinimo', 'MONEY') AS SaldoMinimo
                 , Node.value('@saldo_final', 'MONEY') AS SaldoFinal
                 , Node.value('@interesesAcumulados', 'MONEY') AS InteresesAcumulados
                 , Node.value('@cantRetiros', 'INT') AS CantRetiros
                 , Node.value('@cantDepositos', 'INT') AS CantDepositos
                 , Node.value('@cantSinpeEntrantes', 'INT') AS CantSinpeEntrantes
                 , Node.value('@cantSinpeSalientes', 'INT') AS CantSinpeSalientes
            FROM @datos.nodes('//Estados_de_Cuenta/Estado_de_Cuenta') AS T(Node)
        ) AS X
        JOIN dbo.Cuenta AS C ON C.NumeroCuenta = X.NumeroCuenta;

        SET @insertadas = @@ROWCOUNT;
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('Estados de cuenta: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas, ' (revise el numero de cuenta)');
            THROW 51005, @msg, 1;
        END

        -- qué cuentas puede ver cada usuario (una cuenta puede verla varios usuarios)

        SET @esperadas = @datos.value('count(//Usuarios_Ver/UsuarioPuedeVer)', 'INT');

        INSERT INTO dbo.UsuarioPuedeVer (IdUsuario, IdCuenta)
        SELECT U.IdUsuario, C.IdCuenta
        FROM (
            SELECT Node.value('@User', 'VARCHAR(64)') AS UserName
                 , Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
            FROM @datos.nodes('//Usuarios_Ver/UsuarioPuedeVer') AS T(Node)
        ) AS X
        JOIN dbo.Usuario AS U ON U.UserName = X.UserName
        JOIN dbo.Cuenta  AS C ON C.NumeroCuenta = X.NumeroCuenta;

        SET @insertadas = @@ROWCOUNT;
        IF @insertadas <> @esperadas
        BEGIN
            SET @msg = CONCAT('UsuarioPuedeVer: el XML trae ', @esperadas, ' filas pero se insertaron ', @insertadas, ' (revise usuario o cuenta)');
            THROW 51006, @msg, 1;
        END

        -- todo cargó completo, entonces se confirman los cambios
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO