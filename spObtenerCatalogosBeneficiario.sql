-- Devuelve dos resultados: parentescos y tipos de documento
CREATE OR ALTER PROCEDURE dbo.spObtenerCatalogosBeneficiario
AS
BEGIN
    SET NOCOUNT ON;
    SELECT IdParentesco, Nombre FROM dbo.Parentesco ORDER BY Nombre;
    SELECT IdTipoDocuIdentidad, Nombre FROM dbo.TipoDocuIdentidad ORDER BY IdTipoDocuIdentidad;
END;
GO