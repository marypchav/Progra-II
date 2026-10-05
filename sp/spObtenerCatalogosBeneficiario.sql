CREATE OR ALTER   PROCEDURE [dbo].[spObtenerCatalogosBeneficiario]
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- primer resultado: parentescos, ordenados por nombre
    SELECT IdParentesco, Nombre FROM dbo.Parentesco ORDER BY Nombre;

    -- segundo resultado: tipos de documento, ordenados por id
    SELECT IdTipoDocuIdentidad, Nombre FROM dbo.TipoDocuIdentidad ORDER BY IdTipoDocuIdentidad;
END;
GO