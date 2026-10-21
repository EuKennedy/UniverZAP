# Ver listas é de qualquer pessoa da conta; criar, mexer em membros, importar,
# extrair de grupo, mesclar e apagar é de administrador — como os disparos,
# que são para onde essas listas vão.
class ContactListPolicy < ApplicationPolicy
  %i[index? show? members? export? stats? groups?].each do |action|
    define_method(action) { @account_user.present? }
  end

  %i[create? update? destroy? add_members? remove_members? import_csv? refresh? deduplicate? merge? extract_group?].each do |action|
    define_method(action) { @account_user.administrator? }
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account&.id)
    end
  end
end
