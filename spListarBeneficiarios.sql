CREATE OR ALTER PROCEDURE dbo.spListarBeneficiarios
    @IdUsuario     INT
    , @IdCuenta    INT
    , @OutResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;

    IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
    BEGIN SET @OutResultCode = 50014; RETURN; END

    IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                   WHERE U.IdUsuario = @IdUsuario
                     AND (U.EsAdministrador = 1
                          OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                     WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
    BEGIN SET @OutResultCode = 50002; RETURN; END

    SELECT B.IdBeneficiario, P.IdTipoDocuIdentidad, P.ValorDocumentoIdentidad
         , P.Nombre, B.IdParentesco, PA.Nombre AS Parentesco, B.Porcentaje
         , P.FechaNacimiento, P.Email, P.Telefono1, P.Telefono2
    FROM dbo.Beneficiario AS B
    JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
    JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
    WHERE B.IdCuenta = @IdCuenta AND B.FlagActivo = 1
    ORDER BY B.IdBeneficiario;
END;
GO