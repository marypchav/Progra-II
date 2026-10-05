CREATE OR ALTER   PROCEDURE [dbo].[spListarBeneficiarios]
    @IdUsuario     INT -- quién consulta. sirve para verificar el acceso
    , @IdCuenta    INT -- de qué cuenta se listan los beneficiarios
    , @OutResultCode INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito

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

    -- devuelve los beneficiarios activos. Beneficiario solo guarda la relación entre la cuenta y la persona, por eso se une con Persona (nombre, documento, contacto) y con Parentesco (el nombre del parentesco, para mostrarlo)

    SELECT B.IdBeneficiario, P.IdTipoDocuIdentidad, P.ValorDocumentoIdentidad
         , P.Nombre, B.IdParentesco, PA.Nombre AS Parentesco, B.Porcentaje
         , P.FechaNacimiento, P.Email, P.Telefono1, P.Telefono2
    FROM dbo.Beneficiario AS B
    JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
    JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
    WHERE B.IdCuenta = @IdCuenta AND B.FlagActivo = 1
    ORDER BY B.IdBeneficiario; -- orden estable: el más antiguo primero
END;
GO