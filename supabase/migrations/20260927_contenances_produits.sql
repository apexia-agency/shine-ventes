-- Contenances manquantes des produits de chimie (produits.contenance_l, en litres), tirées de la référence
-- ou du libellé. Ne remplit que les contenances vides : aucune valeur existante n'est modifiée.
-- Aérosols : volume net (400 ou 500 ml), le board les regroupe dans une seule ligne « Aérosols ».
-- Laissés vides exprès : cire, polish et Inoxal (au poids), MC42-150 (référence 150 ml mais libellé 450 ml, à trancher),
-- SHTC14-650 (volume net inconnu), packs classés en chimie, produits sans format lisible.

update produits p
set contenance_l = v.l
from (values
  -- Aérosols (volume net)
  ('AS1005-A650-500', 0.5), ('AS1006-A650-400', 0.4), ('AS1006-A650-500', 0.5), ('AS1007-A520-400', 0.4),
  ('AS1008-A650-500', 0.5), ('AS1008-A650-500-12', 0.5), ('AS1010-A650-500', 0.5), ('AS1010V-A650-500', 0.5),
  ('AS14-A650', 0.4), ('AS19-A650', 0.5), ('AS32-A650', 0.5), ('AS35-A650', 0.5), ('AS35V-A650-500', 0.5),
  ('AS47-A650-400', 0.4),
  -- SHINE : petits formats et autres
  ('AD1-200', 0.2), ('AD2-200', 0.2), ('AS04-250', 0.25), ('AS14-450', 0.45), ('AS14-750', 0.75),
  ('AS23-200', 0.2), ('AS24-200', 0.2), ('AS25-200', 0.2), ('AS33-100', 0.1), ('AS34-50', 0.05),
  ('AS36-450', 0.45), ('AS37-250', 0.25), ('AS38-50', 0.05), ('AS39-100', 0.1), ('AS43-150', 0.15),
  ('AS53-150', 0.15), ('AS54-150', 0.15), ('ASC01-PAE-750', 0.75), ('ASC02-PAE-750', 0.75),
  ('AS01-750-V', 0.75), ('AS10-750-V', 0.75), ('AS26-750-V', 0.75), ('AS16-25', 25),
  -- MyClear
  ('MC03-450', 0.45), ('MC05-450', 0.45), ('MC06-450', 0.45), ('MC09-450', 0.45), ('MC10-450', 0.45),
  ('MC17-450', 0.45), ('MC21-450', 0.45), ('MC22-450', 0.45), ('MC28-450', 0.45),
  -- Marques distributeur : Clean Auto, Ceika, DPF, Netexpert, Shiftec, Sunshine
  ('CKA1001-450', 0.45),
  ('CLC001-450', 0.45), ('CLC001-900', 0.9), ('CLC001-5', 5), ('CLC002-250', 0.25), ('CLC002-900', 0.9),
  ('CLC003-5', 5), ('CLC006-450', 0.45), ('CLC006-900', 0.9), ('CLC006-5', 5), ('CLC007-900', 0.9), ('CLC007-5', 5),
  ('CLC008-450', 0.45), ('CLC010-900', 0.9), ('CLC010-5', 5), ('CLC011-750', 0.75), ('CLC012-900', 0.9),
  ('CLC013-450', 0.45), ('CLC013-5', 5), ('CLC014-450', 0.45), ('CLC014-900', 0.9), ('CLC014-5', 5),
  ('CLC017-50', 0.05), ('CLC018-900', 0.9), ('CLC020-500', 0.5), ('CLC021-500', 0.5), ('CLC022-500', 0.5),
  ('CLC026-500', 0.5), ('CLC027-200', 0.2), ('CLC029-450', 0.45), ('CLC029-900', 0.9), ('CLC029-5', 5),
  ('DPF001-450', 0.45), ('DPF007-900', 0.9), ('DPF014-450', 0.45),
  ('NET03-450', 0.45), ('NET03-900', 0.9), ('NET05-450', 0.45), ('NET05-900', 0.9), ('NET08-450', 0.45),
  ('NET08-900', 0.9), ('NET09-450', 0.45), ('NET09-750', 0.75), ('NET12-450', 0.45), ('NET12-750', 0.75),
  ('NET28-450', 0.45), ('NET28-900', 0.9),
  ('SHTC01-450', 0.45), ('SHTC03-450', 0.45), ('SHTC05-450', 0.45), ('SHTC06-450', 0.45), ('SHTC08-450', 0.45),
  ('SHTC09-450', 0.45), ('SHTC10-450', 0.45), ('SHTC12-450', 0.45), ('SHTC19-450', 0.45), ('SHTC21-450', 0.45),
  ('SHTC22-450', 0.45), ('SHTC26-450', 0.45), ('SHTC29-450', 0.45), ('SHTC31-450', 0.45), ('SHTC37-450', 0.45),
  ('SUN03-450', 0.45), ('SUN06-450', 0.45), ('SUN26-450', 0.45), ('SUN29-450', 0.45), ('SUN31-450', 0.45)
) as v(sku, l)
where p.sku = v.sku and p.contenance_l is null;
