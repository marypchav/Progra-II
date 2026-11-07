CREATE OR ALTER PROCEDURE dbo.spProcesarFecha
    @inFechaOperacion DATE -- fecha de operación que se procesa
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spProcesarFecha
        @inFechaOperacion = '2026-03-01'
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
        DECLARE @primeraFecha DATE
            , @ultimoId INT
            , @idActual INT
            , @tipoNodo VARCHAR(32)
            , @nodo XML
            , @codigoNodo INT
            , @idEstadoCuenta INT
            , @resultadoCierre INT;

        -- variables con los datos de un nodo
        DECLARE @valorDocumento VARCHAR(32)
            , @numeroCuenta VARCHAR(20)
            , @userName VARCHAR(64)
            , @idCuenta INT
            , @idTipoMovimiento INT
            , @monto MONEY
            , @descripcion NVARCHAR(128);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- debe estar cargado el XML de operaciones
        SELECT @primeraFecha = MIN(OX.FechaOperacion)
        FROM dbo.OperacionXML AS OX;

        IF (@primeraFecha IS NULL)
        BEGIN
            SET @outResultCode = 52017; -- no se ha cargado el XML de operaciones
            RETURN;
        END;

        -- una fecha terminada no se vuelve a procesar
        IF EXISTS (
            SELECT 1
            FROM dbo.ControlSimulacion AS CS
            WHERE (CS.FechaOperacion = @inFechaOperacion)
                AND (CS.FlagTerminado = @true)
        )
        BEGIN
            SET @outResultCode = 52013; -- fecha ya procesada
            RETURN;
        END;

        -- las fechas van en orden: la anterior debe estar terminada
        IF (@inFechaOperacion < @primeraFecha)
            OR (
                (@inFechaOperacion > @primeraFecha)
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.ControlSimulacion AS CS
                    WHERE (CS.FechaOperacion = DATEADD(DAY, -1, @inFechaOperacion))
                        AND (CS.FlagTerminado = @true)
                )
            )
        BEGIN
            SET @outResultCode = 52014; -- fecha fuera de orden
            RETURN;
        END;

        -- preprocesamiento
        -- registro de control de la fecha (si se está reiniciando, ya existe)
        INSERT INTO dbo.ControlSimulacion (
            FechaOperacion
            , UltimoIdOperacionXML
        )
        SELECT @inFechaOperacion
            , 0
        WHERE NOT EXISTS (
            SELECT 1
            FROM dbo.ControlSimulacion AS CS
            WHERE (CS.FechaOperacion = @inFechaOperacion)
        );

        -- último nodo aplicado de esta fecha (0 si es la primera vez)
        SELECT @ultimoId = ISNULL(CS.UltimoIdOperacionXML, 0)
        FROM dbo.ControlSimulacion AS CS
        WHERE (CS.FechaOperacion = @inFechaOperacion);

        -- 1. nodos de la fecha, uno por uno, desde el siguiente al último aplicado
        SELECT @idActual = MIN(OX.IdOperacionXML)
        FROM dbo.OperacionXML AS OX
        WHERE (OX.FechaOperacion = @inFechaOperacion)
            AND (OX.IdOperacionXML > @ultimoId);

        WHILE (@idActual IS NOT NULL)
        BEGIN

            SELECT @tipoNodo = OX.TipoNodo
                , @nodo = OX.Nodo
            FROM dbo.OperacionXML AS OX
            WHERE (OX.IdOperacionXML = @idActual);

            SET @codigoNodo = 0;

            -- transacción por nodo: el cambio y el avance del control van juntos
            BEGIN TRANSACTION tProcesarNodo;

                IF (@tipoNodo = 'Persona')
                BEGIN
                    -- la persona se inserta solo si no existe
                    SET @valorDocumento = @nodo.value('(/Persona/@ValorDocumentoIdentidad)[1]', 'VARCHAR(32)');

                    INSERT INTO dbo.Persona (
                        IdTipoDocuIdentidad
                        , ValorDocumentoIdentidad
                        , Nombre
                        , FechaNacimiento
                        , Email
                        , Telefono1
                        , Telefono2
                    )
                    SELECT @nodo.value('(/Persona/@TipoDocuIdentidad)[1]', 'INT')
                        , @valorDocumento
                        , @nodo.value('(/Persona/@Nombre)[1]', 'VARCHAR(64)')
                        , @nodo.value('(/Persona/@FechaNacimiento)[1]', 'DATE')
                        , @nodo.value('(/Persona/@Email)[1]', 'VARCHAR(64)')
                        , @nodo.value('(/Persona/@telefono1)[1]', 'VARCHAR(64)')
                        , @nodo.value('(/Persona/@telefono2)[1]', 'VARCHAR(64)')
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM dbo.Persona AS P
                        WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                    );
                END
                ELSE IF (@tipoNodo = 'Cuenta')
                BEGIN
                    -- el dueño debe existir. al insertar, el trigger abre el primer estado
                    SET @valorDocumento = @nodo.value('(/Cuenta/@ValorDocumentoIdentidadDelCliente)[1]', 'VARCHAR(32)');
                    SET @numeroCuenta = @nodo.value('(/Cuenta/@NumeroCuenta)[1]', 'VARCHAR(20)');

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.Persona AS P
                        WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                    )
                    BEGIN
                        SET @codigoNodo = 52015; -- referencia inexistente
                    END;

                    INSERT INTO dbo.Cuenta (
                        NumeroCuenta
                        , IdPersonaDueno
                        , IdTipoCuentaAhorro
                        , FechaCreacion
                        , Saldo
                    )
                    SELECT @numeroCuenta
                        , P.IdPersona
                        , @nodo.value('(/Cuenta/@TipoCuentaId)[1]', 'INT')
                        , @nodo.value('(/Cuenta/@FechaCreacion)[1]', 'DATE')
                        , @nodo.value('(/Cuenta/@Saldo)[1]', 'MONEY')
                    FROM dbo.Persona AS P
                    WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                        AND NOT EXISTS (
                            SELECT 1
                            FROM dbo.Cuenta AS C
                            WHERE (C.NumeroCuenta = @numeroCuenta)
                        );
                END
                ELSE IF (@tipoNodo = 'Beneficiario')
                BEGIN
                    -- la cuenta y la persona deben existir
                    SET @numeroCuenta = @nodo.value('(/Beneficiario/@NumeroCuenta)[1]', 'VARCHAR(20)');
                    SET @valorDocumento = @nodo.value('(/Beneficiario/@ValorDocumentoIdentidadBeneficiario)[1]', 'VARCHAR(32)');

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.Cuenta AS C
                        WHERE (C.NumeroCuenta = @numeroCuenta)
                    )
                        OR NOT EXISTS (
                            SELECT 1
                            FROM dbo.Persona AS P
                            WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                        )
                    BEGIN
                        SET @codigoNodo = 52015; -- referencia inexistente
                    END;

                    -- FlagActivo toma su default (1)
                    INSERT INTO dbo.Beneficiario (
                        IdCuenta
                        , IdPersonaBeneficiario
                        , IdParentesco
                        , Porcentaje
                    )
                    SELECT C.IdCuenta
                        , P.IdPersona
                        , @nodo.value('(/Beneficiario/@IdParentezco)[1]', 'INT')
                        , @nodo.value('(/Beneficiario/@Porcentaje)[1]', 'INT')
                    FROM dbo.Cuenta AS C
                    INNER JOIN dbo.Persona AS P
                        ON (P.ValorDocumentoIdentidad = @valorDocumento)
                    WHERE (C.NumeroCuenta = @numeroCuenta)
                        AND NOT EXISTS (
                            SELECT 1
                            FROM dbo.Beneficiario AS B
                            WHERE (B.IdCuenta = C.IdCuenta)
                                AND (B.IdPersonaBeneficiario = P.IdPersona)
                                AND (B.FlagActivo = @true)
                        );
                END
                ELSE IF (@tipoNodo = 'Usuario')
                BEGIN
                    -- la persona del usuario debe existir
                    SET @valorDocumento = @nodo.value('(/Usuario/@ValorDocId)[1]', 'VARCHAR(32)');
                    SET @userName = @nodo.value('(/Usuario/@User)[1]', 'VARCHAR(64)');

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.Persona AS P
                        WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                    )
                    BEGIN
                        SET @codigoNodo = 52015; -- referencia inexistente
                    END;

                    INSERT INTO dbo.Usuario (
                        UserName
                        , Pass
                        , EsAdministrador
                        , IdPersona
                    )
                    SELECT @userName
                        , @nodo.value('(/Usuario/@Pass)[1]', 'VARCHAR(64)')
                        , @nodo.value('(/Usuario/@EsAdministrador)[1]', 'BIT')
                        , P.IdPersona
                    FROM dbo.Persona AS P
                    WHERE (P.ValorDocumentoIdentidad = @valorDocumento)
                        AND NOT EXISTS (
                            SELECT 1
                            FROM dbo.Usuario AS U
                            WHERE (U.UserName = @userName)
                        );
                END
                ELSE IF (@tipoNodo = 'UsuarioPuedeVer')
                BEGIN
                    -- el usuario y la cuenta deben existir
                    SET @userName = @nodo.value('(/UsuarioPuedeVer/@User)[1]', 'VARCHAR(64)');
                    SET @numeroCuenta = @nodo.value('(/UsuarioPuedeVer/@NumeroCuenta)[1]', 'VARCHAR(20)');

                    IF NOT EXISTS (
                        SELECT 1
                        FROM dbo.Usuario AS U
                        WHERE (U.UserName = @userName)
                    )
                        OR NOT EXISTS (
                            SELECT 1
                            FROM dbo.Cuenta AS C
                            WHERE (C.NumeroCuenta = @numeroCuenta)
                        )
                    BEGIN
                        SET @codigoNodo = 52015; -- referencia inexistente
                    END;

                    INSERT INTO dbo.UsuarioPuedeVer (
                        IdUsuario
                        , IdCuenta
                    )
                    SELECT U.IdUsuario
                        , C.IdCuenta
                    FROM dbo.Usuario AS U
                    INNER JOIN dbo.Cuenta AS C
                        ON (C.NumeroCuenta = @numeroCuenta)
                    WHERE (U.UserName = @userName)
                        AND NOT EXISTS (
                            SELECT 1
                            FROM dbo.UsuarioPuedeVer AS UPV
                            WHERE (UPV.IdUsuario = U.IdUsuario)
                                AND (UPV.IdCuenta = C.IdCuenta)
                        );
                END
                ELSE IF (@tipoNodo = 'Movimientos')
                BEGIN
                    -- el XML trae el número de cuenta y el nombre del tipo: se
                    -- traducen a sus Ids. si no existen quedan en NULL y
                    -- spAplicarMovimiento devuelve el código de error
                    SET @numeroCuenta = LTRIM(RTRIM(@nodo.value('(/Movimientos/@CodigoCuenta)[1]', 'VARCHAR(20)')));
                    SET @idCuenta = NULL;
                    SET @idTipoMovimiento = NULL;

                    SELECT @idCuenta = C.IdCuenta
                    FROM dbo.Cuenta AS C
                    WHERE (C.NumeroCuenta = @numeroCuenta);

                    SELECT @idTipoMovimiento = TM.IdTipoMovimiento
                    FROM dbo.TipoMovimiento AS TM
                    WHERE (TM.Nombre = LTRIM(RTRIM(@nodo.value('(/Movimientos/@Tipo)[1]', 'VARCHAR(64)'))));

                    SET @monto = @nodo.value('(/Movimientos/@Monto)[1]', 'MONEY');
                    SET @descripcion = @nodo.value('(/Movimientos/@Descripcion)[1]', 'NVARCHAR(128)');

                    EXEC dbo.spAplicarMovimiento
                        @inIdCuenta = @idCuenta
                        , @inIdTipoMovimiento = @idTipoMovimiento
                        , @inMonto = @monto
                        , @inDescripcion = @descripcion
                        , @inFechaOperacion = @inFechaOperacion
                        , @inIdOperacionXML = @idActual
                        , @outResultCode = @codigoNodo OUTPUT;
                END;

                -- nodo rechazado: queda registrado con su código y se sigue
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
                SELECT SUSER_SNAME()
                    , @codigoNodo
                    , 0
                    , 0
                    , 0
                    , 'spProcesarFecha'
                    , CONCAT('Nodo rechazado. IdOperacionXML ', @idActual
                        , ' (', @tipoNodo, '): ', CAST(@nodo AS NVARCHAR(1000)))
                    , GETDATE()
                WHERE (@codigoNodo <> 0);

                -- avance del control: este nodo ya quedó aplicado
                UPDATE dbo.ControlSimulacion
                SET UltimoIdOperacionXML = @idActual
                WHERE (FechaOperacion = @inFechaOperacion);

            COMMIT TRANSACTION tProcesarNodo;

            -- siguiente nodo de la fecha
            SELECT @idActual = MIN(OX.IdOperacionXML)
            FROM dbo.OperacionXML AS OX
            WHERE (OX.FechaOperacion = @inFechaOperacion)
                AND (OX.IdOperacionXML > @idActual);

        END;

        -- 2. cierres: estados abiertos que terminan hoy. cada cierre corre en
        -- su propia transacción dentro de spCerrarEstadoCuenta y abre el
        -- estado siguiente, que ya no cumple la condición del WHILE
        SELECT @idEstadoCuenta = MIN(EC.IdEstadoCuenta)
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.FlagAbierto = @true)
            AND (EC.FechaFin <= @inFechaOperacion);

        WHILE (@idEstadoCuenta IS NOT NULL)
        BEGIN

            EXEC dbo.spCerrarEstadoCuenta
                @inIdEstadoCuenta = @idEstadoCuenta
                , @inFechaOperacion = @inFechaOperacion
                , @outResultCode = @resultadoCierre OUTPUT;

            -- si un cierre falla se detiene la fecha (el detalle queda en dbError);
            -- al volver a correrla se reintentan los cierres pendientes
            IF (@resultadoCierre <> 0)
            BEGIN
                SET @outResultCode = 52016; -- falló el cierre de un estado
                RETURN;
            END;

            SELECT @idEstadoCuenta = MIN(EC.IdEstadoCuenta)
            FROM dbo.EstadoCuenta AS EC
            WHERE (EC.FlagAbierto = @true)
                AND (EC.FechaFin <= @inFechaOperacion);

        END;

        -- 3. la fecha quedó completa
        UPDATE dbo.ControlSimulacion
        SET FlagTerminado = @true
            , FechaFinProceso = GETDATE()
        WHERE (FechaOperacion = @inFechaOperacion);

    END TRY
    BEGIN CATCH

        -- se deshace solo el nodo que estaba a medias; los anteriores ya
        -- quedaron confirmados y el control apunta al último bueno
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