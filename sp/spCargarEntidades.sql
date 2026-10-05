
CREATE OR ALTER   PROCEDURE [dbo].[spCargarEntidades]
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    BEGIN TRY
        DECLARE @datos XML; -- variable que guardará el contenido completo del XML

        -- lee el archivo completo como binario y lo convierte a XML

        SELECT @datos = BulkColumn
        FROM OPENROWSET(BULK 'C:\Temp\entidades.xml', SINGLE_BLOB) AS x;

        -- todas las cargas van en una transacción: si una falla, no queda nada a medias

        BEGIN TRANSACTION;

        -- personas. son dueños de cuenta y beneficiarios a la vez. El tipo de documento es un id de catálogo que viene tal cual en el XML

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
        FROM @datos.nodes('/Datos/Personas/Persona') AS T(Node);

        -- usuarios. El XML trae el documento de la persona asociada (ValorDocId)

        INSERT INTO dbo.Usuario (UserName, Pass, EsAdministrador, IdPersona)
        SELECT X.UserName, X.Pass, X.EsAdministrador, P.IdPersona
        FROM (
            SELECT Node.value('@User', 'VARCHAR(64)') AS UserName
                 , Node.value('@Pass', 'VARCHAR(64)') AS Pass
                 , Node.value('@EsAdministrador', 'BIT') AS EsAdministrador   -- 1 = administrador, 0 = cliente
                 , Node.value('@ValorDocId', 'VARCHAR(32)') AS Doc
            FROM @datos.nodes('/Datos/Usuarios/Usuario') AS T(Node)
        ) AS X
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        -- cuentas. El XML trae el documento del cliente dueño; el JOIN con Persona lo convierte en IdPersonaDueno

        INSERT INTO dbo.Cuenta
            (NumeroCuenta, IdPersonaDueno, IdTipoCuentaAhorro, FechaCreacion, Saldo)
        SELECT X.NumeroCuenta, P.IdPersona, X.TipoCuentaId, X.FechaCreacion, X.Saldo
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@ValorDocumentoIdentidadDelCliente', 'VARCHAR(32)') AS Doc
                 , Node.value('@TipoCuentaId', 'INT') AS TipoCuentaId
                 , Node.value('@FechaCreacion', 'DATE') AS FechaCreacion
                 , Node.value('@Saldo', 'MONEY') AS Saldo
            FROM @datos.nodes('/Datos/Cuentas/Cuenta') AS T(Node)
        ) AS X
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        -- beneficiarios. No se lista FlagActivo: toma su DEFAULT (1 = activo)

        INSERT INTO dbo.Beneficiario (IdCuenta, IdPersonaBeneficiario, IdParentesco, Porcentaje)
        SELECT C.IdCuenta, P.IdPersona, X.IdParentezco, X.Porcentaje
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@ValorDocumentoIdentidadBeneficiario', 'VARCHAR(32)') AS Doc
                 , Node.value('@IdParentezco', 'INT') AS IdParentezco
                 , Node.value('@Porcentaje', 'INT') AS Porcentaje
            FROM @datos.nodes('/Datos/Beneficiarios/Beneficiario') AS T(Node)
        ) AS X
        JOIN dbo.Cuenta  AS C ON C.NumeroCuenta = X.NumeroCuenta
        JOIN dbo.Persona AS P ON P.ValorDocumentoIdentidad = X.Doc;

        -- estados de cuenta. El número de cuenta se traduce a IdCuenta con el JOIN

        INSERT INTO dbo.EstadoCuenta
            (IdCuenta, FechaInicio, FechaFin, SaldoInicial, SaldoFinal, SaldoMinimo, FechaEmision)
        SELECT C.IdCuenta, X.FechaInicio, X.FechaFin, X.SaldoInicial,
               X.SaldoFinal, X.SaldoMinimo, X.FechaFin
        FROM (
            SELECT Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
                 , Node.value('@fechaInicio', 'DATE') AS FechaInicio
                 , Node.value('@fechafin', 'DATE') AS FechaFin
                 , Node.value('@saldoinicial', 'MONEY') AS SaldoInicial
                 , Node.value('@saldoMinimo', 'MONEY') AS SaldoMinimo
                 , Node.value('@saldo_final', 'MONEY') AS SaldoFinal
            FROM @datos.nodes('/Datos/Estados_de_Cuenta/Estado_de_Cuenta') AS T(Node)
        ) AS X
        JOIN dbo.Cuenta AS C ON C.NumeroCuenta = X.NumeroCuenta;

        -- qué cuentas puede ver cada usuario (UsuarioPuedeVer). Es una tabla intermedia en donde una cuenta puede ser vista por varios usuarios y un usuario puede ver varias cuentas

        INSERT INTO dbo.UsuarioPuedeVer (IdUsuario, IdCuenta)
        SELECT U.IdUsuario, C.IdCuenta
        FROM (
            SELECT Node.value('@User', 'VARCHAR(64)') AS UserName
                 , Node.value('@NumeroCuenta', 'VARCHAR(20)') AS NumeroCuenta
            FROM @datos.nodes('/Datos/Usuarios_Ver/UsuarioPuedeVer') AS T(Node)
        ) AS X
        JOIN dbo.Usuario AS U ON U.UserName = X.UserName
        JOIN dbo.Cuenta  AS C ON C.NumeroCuenta = X.NumeroCuenta;

        -- se confirman los cambios

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

        -- si algo falló se deshace todo y THROW vuelve a lanzar el error original

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO